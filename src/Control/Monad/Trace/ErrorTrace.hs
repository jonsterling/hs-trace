{-# LANGUAGE UnicodeSyntax #-}
{-# LANGUAGE RecordWildCards #-}

module Control.Monad.Trace.ErrorTrace
( ErrorTrace(..)
, _ErrorTrace
, etError
, etTrace
) where

import Control.Applicative
import qualified Data.Foldable as F
import Data.Monoid
import Data.Profunctor
import Data.Sequence as S
import Data.List

-- | A datatype containing an error and its provenience(s).
--
data ErrorTrace t e
  = ErrorTrace
  { _etError ∷ !e -- ^ The error
  , _etTrace ∷ ![Seq t] -- ^ The list of traces (for each path tried)
  }

instance Monoid e ⇒ Monoid (ErrorTrace t e) where
  mempty = ErrorTrace mempty mempty
  mappend (ErrorTrace e tr) (ErrorTrace e' tr') = ErrorTrace (e <> e') (tr <> tr')

instance (Show t, Show e) ⇒ Show (ErrorTrace t e) where
  showsPrec p ErrorTrace{..} =
    showParen (p > 10) $
      foldr (.) id (intersperse (" ∥ "++) $ (foldr (.) id . fmap shows . F.toList) <$> _etTrace)
      . (" ⇑ " ++)
      . shows _etError

-- | An isomorphism @'ErrorTrace' t e ≅ (e, 'Seq' t)@.
--
_ErrorTrace
  ∷ ( Choice p
    , Functor f
    )
  ⇒ p (ErrorTrace t e) (f (ErrorTrace t' e'))
  → p (e, [Seq t]) (f (e', [Seq t']))
_ErrorTrace =
  dimap (uncurry ErrorTrace)
  . fmap $ \ErrorTrace{..} → (_etError, _etTrace)

-- | A lens @'ErrorTrace' t e → e@.
--
etError
  ∷ Functor f
  ⇒ (e → f e')
  → ErrorTrace t e
  → f (ErrorTrace t e')
etError inj ErrorTrace{..} =
  flip ErrorTrace _etTrace
    <$> inj _etError

-- | A lens @'ErrorTrace' t e → Seq t@.
--
etTrace
  ∷ Functor f
  ⇒ ([Seq t] → f [Seq t'])
  → ErrorTrace t e
  → f (ErrorTrace t' e)
etTrace inj ErrorTrace{..} =
  ErrorTrace _etError
    <$> inj _etTrace

