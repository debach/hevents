{-# LANGUAGE ScopedTypeVariables #-}
module Hevents.Eff.EffSpec(spec) where

import           Control.Concurrent.STM
import           Control.Eff             as E
import           Control.Eff.Lift        as E
import           Control.Monad           ((<=<))
import           Data.Either
import           Data.Serialize
import           Debug.Trace
import           Hevents.Eff             as S hiding (get)
import           Hevents.Eff.TestModel   as M
import           Hevents.Eff.TestStore   as T
import           Test.Hspec
import           Test.QuickCheck         as Q
import           Test.QuickCheck.Monadic as Q

prop_combineStateAndStorage :: [ Command TestModel ] -> Property
prop_combineStateAndStorage commands = Q.monadicIO $ do
  storage <- initialiseStorage
  let
    asDBError OutOfBounds = IOError "out of bounds"
    acts :: Eff (Store :> State TestModel :> r) TestModel
    acts = do
      r <- mapM (either (return . Left . asDBError) store <=< applyCommand) commands
      trace (show r) $ getState
  m <- Q.run $ atomically $ newTVar (S.init :: TestModel) >>= \ m -> (runLift  . runState m . runStore storage) acts
  stored :: [ Event TestModel ] <- Q.run $ atomically $ (rights . map (runGet get)) <$> readMemoryStore storage

  let storedVal = foldl apply S.init $ reverse stored

  Q.run $ putStrLn $ "stored "++ show stored++ ", model=" ++ show m ++ ", storedVal="++ show storedVal++ ", commands="++ show commands

  assert $ m == storedVal

  where
    initialiseStorage = Q.run $ atomically $ T.makeMemoryStore

spec :: Spec
spec = describe "Combined State & Store Effect" $ do

  it "should abort state update when underlying storage fails" $ property $ prop_combineStateAndStorage


