{-# LANGUAGE UndecidableInstances #-}

module BitMEXClient.Wrapper.Types
    ( BitMEXWrapperConfig(..)
    , BitMEXReader(..)
    , Environment(..)
    , BitMEXApp
    , Authenticator(..)
    , APIKeys(..)
    , run
    ) where

import           BitMEX
    ( AuthApiKeyApiKey (..)
    , AuthApiKeyApiNonce (..)
    , AuthApiKeyApiSignature (..)
    , BitMEXConfig (..)
    , LogContext
    , addAuthMethod
    )
import           BitMEXClient.CustomPrelude
import           BitMEXClient.Wrapper.Util
import qualified Data.ByteString            as BS
    ( ByteString
    )
import qualified Data.ByteString.Char8      as BC (pack)
import qualified Data.ByteString.Lazy       as LBS
    ( ByteString
    )
import           Data.Text                  (Text)
import qualified Data.Text                  as T (pack)

data Environment
    = MainNet
    | TestNet
    deriving (Eq)

instance Show Environment where
    show MainNet = "https://www.bitmex.com"
    show TestNet = "https://testnet.bitmex.com"

class Monad m => Authenticator m where
    authRESTConfig ::
           (ByteArrayAccess a)
        => BitMEXConfig
        -> a
        -> m BitMEXConfig
    authWSMessage :: Int -> m [Value]

newtype AuthReader m a =
    AuthReader (m a)
    deriving (Functor, Applicative, Monad)

instance (HasReader "apiKeys" APIKeys m, MonadIO m) =>
         Authenticator (AuthReader m) where
    authRESTConfig config msg =
        coerce @(m BitMEXConfig) $ do
            APIKeys {..} <- ask @"apiKeys"
            let sig = sign privateKey msg :: Digest SHA256
            return $
                config `addAuthMethod`
                AuthApiKeyApiSignature ((T.pack . show) sig) `addAuthMethod`
                AuthApiKeyApiNonce "" `addAuthMethod`
                AuthApiKeyApiKey publicKey
    authWSMessage time =
        coerce @(m [Value]) $ do
            APIKeys {..} <- ask @"apiKeys"
            let msg =
                    BC.pack
                        ("GET" <> "/realtime" <> show time)
                sig = sign privateKey msg :: Digest SHA256
            return
                [ String publicKey
                , toJSON time
                , (toJSON . show) sig
                ]

data APIKeys = APIKeys
    { publicKey  :: !Text
    , privateKey :: !BS.ByteString
    } deriving (Generic)

data BitMEXWrapperConfig = BitMEXWrapperConfig
    { environment :: !Environment
    , pathREST    :: !(Maybe LBS.ByteString)
    , pathWS      :: !(Maybe LBS.ByteString)
    , manager     :: !(Maybe Manager)
    , apiKeys     :: !APIKeys
    , logContext  :: !LogContext
    } deriving (Generic)

newtype BitMEXReader a = BitMEXReader
    (ReaderT BitMEXWrapperConfig IO a)
    deriving (Functor, Applicative, Monad, MonadIO)
    deriving Authenticator via
        AuthReader (Field "apiKeys" ()
        (MonadReader (ReaderT BitMEXWrapperConfig IO)))
    deriving (HasReader "environment" Environment) via
        Field "environment" ()
        (MonadReader (ReaderT BitMEXWrapperConfig IO))
    deriving (HasReader "pathREST" (Maybe LBS.ByteString)) via
        Field "pathREST" ()
        (MonadReader (ReaderT BitMEXWrapperConfig IO))
    deriving (HasReader "pathWS" (Maybe LBS.ByteString)) via
        Field "pathWS" ()
        (MonadReader (ReaderT BitMEXWrapperConfig IO))
    deriving (HasReader "manager" (Maybe Manager)) via
        Field "manager" ()
        (MonadReader (ReaderT BitMEXWrapperConfig IO))
    deriving (HasReader "apiKeys" APIKeys) via
        Field "apiKeys" ()
        (MonadReader (ReaderT BitMEXWrapperConfig IO))
    deriving (HasReader "publicKey" Text) via
        Field "publicKey" "apiKeys"
        (Field "apiKeys" ()
        (MonadReader (ReaderT BitMEXWrapperConfig IO)))
    deriving (HasReader "privateKey" BS.ByteString) via
        Field "privateKey" "apiKeys"
        (Field "apiKeys" ()
        (MonadReader (ReaderT BitMEXWrapperConfig IO)))
    deriving (HasReader "logContext" LogContext) via
        Field "logContext" ()
        (MonadReader (ReaderT BitMEXWrapperConfig IO))
    deriving (HasReader "config" BitMEXWrapperConfig) via
        MonadReader (ReaderT BitMEXWrapperConfig IO)

run :: BitMEXReader a -> BitMEXWrapperConfig -> IO a
run (BitMEXReader m) = runReaderT m

type BitMEXApp a = Connection -> BitMEXReader a
