{-# LANGUAGE FlexibleContexts           #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE MultiParamTypeClasses      #-}
{-# LANGUAGE StandaloneDeriving         #-}

module App.Application where

import App.AppEnv
import App.AppError
import App.AppState
import App.Orphans                  ()
import Arbor.Logger
import Control.Lens
import Control.Monad.Base
import Control.Monad.Catch
import Control.Monad.Except
import Control.Monad.Logger         (LoggingT, MonadLogger)
import Control.Monad.Reader
import Control.Monad.State.Strict   (MonadState (..), StateT, execStateT)
import Control.Monad.Trans.Resource
import Data.Text                    (Text)
import Network.AWS                  as AWS hiding (LogLevel)
import Network.StatsD               as S

type AppName = Text

newtype Application a = Application
  { unApp :: ReaderT AppEnv (StateT AppState (ExceptT AppError (LoggingT AWS))) a
  } deriving ( Functor
             , Applicative
             , Monad
             , MonadIO
             , MonadBase IO
             , MonadThrow
             , MonadCatch
             , MonadReader AppEnv
             , MonadState AppState
             , MonadError AppError
             , MonadAWS
             , MonadLogger
             , MonadResource)

-- This is here to simplify the constraint
-- it also helps to avoid propagating FlexibleContexts requirements
class MonadError AppError m => MonadAppError m where

class ( MonadReader AppEnv m
      , MonadState AppState m
      , MonadLogger m
      , MonadAWS m
      , MonadStats m
      , MonadResource m
      , MonadThrow m
      , MonadCatch m
      , MonadError AppError m
      , MonadAppError m
      , MonadIO m) => MonadApp m where

deriving instance MonadAppError Application
deriving instance MonadApp Application

instance MonadStats Application where
  getStatsClient = reader _appEnvStatsClient

runApplicationM :: AppEnv
                -> Application ()
                -> IO (Either AppError AppState)
runApplicationM envApp f =
  runResourceT
    . runAWS (envApp ^. appEnvAwsEnv)
    . runTimedLogT (envApp ^. appLogger . appLoggerLogLevel) (envApp ^. appLogger . appLoggerLogger)
    . runExceptT
    . flip execStateT appStateEmpty
    $ do
        logInfo $ show (envApp ^. appEnvOptions)
        runReaderT (unApp f) envApp
