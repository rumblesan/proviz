module Tests.GfxInterpreter where

import Test.Framework (Test, testGroup)
import Test.HUnit (Assertion, assertEqual)
import Test.Framework.Providers.HUnit (testCase)

import Data.Map.Strict
import Control.Monad.State.Strict

import Gfx

gfxInterpreterTests :: Test
gfxInterpreterTests =
  testGroup "GFX Interpreter Tests" [
    testCase "Simple interpretation works as expected" test_simple
  ]

test_simple :: Assertion
test_simple =
  let
    state = EngineState { variables=fromList [("time", 2)] }
    shape = Cube (Number 1) (Number 1) (Variable "time")
    shapeblock = Just $ [ShapeCommand shape Nothing]
    matrix = Rotate (Number 1) (Variable "time") (Number 1)
    ast = [MatrixCommand matrix shapeblock]
    expected = ["Rotate,1.0,2.0,1.0 scope enter", "Cube,1.0,1.0,2.0", "Rotate,1.0,2.0,1.0 scope leave"]
  in
    assertEqual "" expected (evalState (interpretGfx ast) state)