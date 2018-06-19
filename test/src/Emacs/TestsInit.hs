-- |
-- Module      :  Emacs.TestsInit
-- Copyright   :  (c) Sergey Vinokurov 2018
-- License     :  BSD3-style (see LICENSE)
-- Maintainer  :  serg.foo@gmail.com
----------------------------------------------------------------------------

{-# LANGUAGE CPP                        #-}
{-# LANGUAGE DataKinds                  #-}
{-# LANGUAGE FlexibleContexts           #-}
{-# LANGUAGE ForeignFunctionInterface   #-}
{-# LANGUAGE GADTs                      #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE OverloadedStrings          #-}
{-# LANGUAGE QuasiQuotes                #-}
{-# LANGUAGE TypeFamilies               #-}

module Emacs.TestsInit () where

import qualified Data.ByteString.Char8 as C8
import Data.Maybe
import Foreign
#if MIN_VERSION_base(4,10,0)
import Foreign.C
#endif

import Data.Emacs.Module.Args
import Data.Emacs.Module.Runtime (Runtime)
import qualified Data.Emacs.Module.Runtime as Runtime
import Data.Emacs.Module.SymbolName.TH
import Emacs.Module
import Emacs.Module.Assert
import Emacs.Module.Errors

#if MIN_VERSION_base(4,10,0)
foreign export ccall initialise :: Ptr Runtime -> IO CBool

true, false :: CBool
true  = CBool 1
false = CBool 0

#else
foreign export ccall initialise :: Ptr Runtime -> IO Int

true, false :: Int
true  = 1
false = 0
#endif

#if MIN_VERSION_base(4,10,0)
initialise :: WithCallStack => Ptr Runtime -> IO CBool
#else
initialise :: WithCallStack => Ptr Runtime -> IO Int
#endif
initialise runtime = do
  runtime' <- Runtime.validateRuntime runtime
  case runtime' of
    Nothing        -> pure false
    Just runtime'' -> do
      env <- Runtime.getEnvironment runtime''
      res <- reportAllErrorsToEmacs env (pure False) $ runEmacsM env initialise'
      pure $ if res then true else false

initialise'
  :: (WithCallStack, Throws EmacsThrow, Throws EmacsError, Throws EmacsInternalError)
  => EmacsM s Bool
initialise' = do
  bindFunction [esym|haskell-emacs-module-tests-apply2|] =<<
    makeFunction apply2 "Apply a function twice."
  bindFunction [esym|haskell-emacs-module-tests-add|] =<<
    makeFunction add "Add two numbers."
  bindFunction [esym|haskell-emacs-module-tests-get-rest|] =<<
    makeFunction getRest "Just return the &rest argument."
  bindFunction [esym|haskell-emacs-module-tests-append-lots-of-strings|] =<<
    makeFunction appendLotsOfStrings "Append foo string N times to itself."
  bindFunction [esym|haskell-emacs-module-tests-append-lots-of-vectors|] =<<
    makeFunction appendLotsOfVectors "Append [1 2 3] vector N times to itself."
  pure True

apply2
  :: (WithCallStack, MonadEmacs m, Monad (m s))
  => EmacsFunction ('S ('S 'Z)) 'Z 'False s m
apply2 (R f (R x Stop)) = do
  y <- funcallPrimitive [esym|funcall|] [f, x]
  funcall [esym|funcall|] [f, y]

add
  :: (WithCallStack, MonadEmacs m, Monad (m s))
  => EmacsFunction ('S ('S 'Z)) 'Z 'False s m
add (R x (R y Stop)) =
  makeInt =<< (+) <$> extractInt x <*> extractInt y

getRest
  :: (WithCallStack, MonadEmacs m, Monad (m s))
  => EmacsFunction ('S 'Z) 'Z 'True s m
getRest (R _req (Rest rest)) =
  funcall [esym|vector|] rest

appendLotsOfStrings
  :: (WithCallStack, MonadEmacs m, Monad (m s), MonadMask (m s))
  => EmacsFunction ('S 'Z) 'Z 'False s m
appendLotsOfStrings (R n Stop) = do
  n'     <- extractInt n
  -- foo'   <- makeString "foo"
  empty' <- makeString ""
  let input = replicate n' (makeString "foo", "foo")
      res = appendTree concat2' input
  res' <- traverse fst res
  pure $ fromMaybe empty' res'

appendLotsOfVectors
  :: (WithCallStack, MonadEmacs m, Monad (m s), MonadMask (m s))
  => EmacsFunction ('S 'Z) 'Z 'False s m
appendLotsOfVectors (R n Stop) = do
  n'     <- extractInt n
  one    <- makeInt 1
  two    <- makeInt 2
  three  <- makeInt 3
  test   <- makeVector [one, two, three]

  empty' <- makeVector []

  let input = replicate n' (pure test, [1, 2, 3])
      res = appendTree vconcat2' input
  res' <- traverse fst res
  pure $ fromMaybe empty' res'


concat2'
  :: (WithCallStack, MonadEmacs m, Monad (m s), MonadMask (m s))
  => (m s (Value s), C8.ByteString)
  -> (m s (Value s), C8.ByteString)
  -> (m s (Value s), C8.ByteString)
concat2' (x, xStr) (y, yStr) =
  (go, xStr <> yStr)
  where
    go = do
      x' <- x
      y' <- y
      withCleanup x' $ \x'' ->
        withCleanup y' $ \y'' -> do
          _ <- funcallPrimitive [esym|garbage-collect|] []
          concat2 x'' y''

vconcat2'
  :: (WithCallStack, MonadEmacs m, Monad (m s), MonadMask (m s))
  => (m s (Value s), [Int])
  -> (m s (Value s), [Int])
  -> (m s (Value s), [Int])
vconcat2' (x, xs) (y, ys) =
  (go, xs <> ys)
  where
    go = do
      x' <- x
      y' <- y
      withCleanup x' $ \x'' ->
        withCleanup y' $ \y'' -> do
          _ <- funcallPrimitive [esym|garbage-collect|] []
          vconcat2 x'' y''


appendTree :: WithCallStack => (a -> a -> a) -> [a] -> Maybe a
appendTree f = reduce
  where
    go []             = []
    go xs@[_]         = xs
    go (x1 : x2 : xs) = f x1 x2 : go xs

    reduce []  = Nothing
    reduce [x] = Just x
    reduce xs  = reduce (go xs)

