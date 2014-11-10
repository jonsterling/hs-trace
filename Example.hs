{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE FunctionalDependencies #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE UnicodeSyntax #-}

module Example where

import Control.Applicative
import Control.Error
import Control.Monad
import Control.Monad.Error
import Control.Monad.Trans.Either
import Control.Monad.State
import Control.Lens
import Data.Monoid
import qualified Data.Sequence as S
import Data.List
import qualified Data.Foldable as F

data Tags
  = FrontEnd
  | BackEnd
  | SetPassword
  | GetUserInfo
  | Dynamo
  deriving Show

newtype TraceT t e m α
  = TraceT
  { _traceT ∷ EitherT (State (S.Seq t) e) m α
  } deriving (Functor, Monad, Applicative, MonadIO, MonadTrans)

makeLenses ''TraceT

class MonadTrace t m | m → t where
  traceScope
    ∷ t
    → m α
    → m α

instance Monad m ⇒ MonadTrace t (TraceT t e m) where
  traceScope t =
    traceT %~ fmapLT (withState (|> t))

instance Monad m ⇒ MonadError e (TraceT t e m) where
  throwError =
    TraceT . throwT . return
  catchError (TraceT m) h =
     lift (runEitherT m)
       >>= either (h . flip evalState mempty) return

class Monad m ⇒ HoistError m t e e' | t → e where
  hoistError
    ∷ t α
    → (e → e')
    → m α

instance MonadError e m ⇒ HoistError m Maybe () e where
  hoistError Nothing f = throwError $ f ()
  hoistError (Just x) _ = return x

instance MonadError e' m ⇒ HoistError m (Either e) e e' where
  hoistError (Left e) f = throwError $ f e
  hoistError (Right x) _ = return x


(<%?>)
  ∷ HoistError m t e e'
  ⇒ t α
  → (e → e')
  → m α
(<%?>) = hoistError

(<%!?>)
  ∷ HoistError m t e e'
  ⇒ m (t α)
  → (e → e')
  → m α
m <%!?> e = do
  x ← m
  x <%?> e

(<?>)
  ∷ HoistError m t e e'
  ⇒ t α
  → e'
  → m α
m <?> e = m <%?> const e

(<!?>)
  ∷ HoistError m t e e'
  ⇒ m (t α)
  → e'
  → m α
m <!?> e = do
  x ← m
  x <?> e

data Err
  = Err String
  deriving Show

data ErrorTrace t e
  = ErrorTrace
  { _etError ∷ e
  , _etTrace ∷ S.Seq t
  }

instance (Show t, Show e) ⇒ Show (ErrorTrace t e) where
  showsPrec p ErrorTrace{..} =
    showParen (p > 10) $
      foldr (.) id (intersperse ('.':) $ shows <$> F.toList _etTrace)
      . (" ⇑ " ++)
      . shows _etError

makeLenses ''ErrorTrace
makePrisms ''ErrorTrace

runTraceT
  ∷ ( Functor m
    , Monad m
    )
  ⇒ TraceT t e m α
  → EitherT (ErrorTrace t e) m α
runTraceT =
  fmapLT (review _ErrorTrace . flip runState mempty)
  . _traceT

annoyingFunction
  ∷ MonadIO m
  ⇒ Int
  → m (Either Int ())
annoyingFunction i =
  return $ Left i

test = do
  traceScope FrontEnd $
    traceScope GetUserInfo $ do
      liftIO $ putStrLn "Hello world"
      annoyingFunction 10 <!?> Err "Damn"
      annoyingFunction 10 <%!?> (Err . show)
      Left "Welp" <%?> Err
      Nothing <?> Err "nothing"


main ∷ IO ()
main =
  runTraceT test
    & eitherT (fail . show) return

-- OUTPUTS
--
--     Hello world
--     *** Exception: user error (FrontEnd.GetUserInfo ⇑ Err "Damn")

