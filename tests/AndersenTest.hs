import Data.Map ( Map )
import Data.Set ( Set )
import qualified Data.Map as M
import qualified Data.Set as S
import Data.Maybe ( fromJust )
import System.FilePath
import Test.HUnit ( assertEqual )

import Data.LLVM
import Data.LLVM.Analysis.PointsTo.Andersen
import Data.LLVM.Analysis.PointsTo
import Data.LLVM.ParseBitcode
import Data.LLVM.Testing

ptPattern = "tests/points-to-inputs/*.c"
expectedMapper = flip replaceExtension ".expected-andersen"
bcParser = parseLLVMBitcodeFile defaultParserOptions

-- extractSummary :: Module -> ExpectedResult
extractSummary m = foldr addInfo M.empty ptrs
  where
    pta = runPointsToAnalysis m
    ptrs = map Value (globalPointerVariables m) ++ map Value (functionPointerParameters m)
    addInfo v r = case S.null vals of
      True -> r
      False -> M.insert (show $ fromJust $ valueName v) vals r
      where
        vals = S.map (show . fromJust . valueName) (pointsTo pta v)

isPointerType t = case t of
  TypePointer _ _ -> True
  TypeNamed _ t' -> isPointerType t'
  _ -> False

isPointer :: (IsValue a) => a -> Bool
isPointer = isPointerType . valueType

globalPointerVariables :: Module -> [GlobalVariable]
globalPointerVariables m = filter isPointer (moduleGlobalVariables m)

functionPointerParameters :: Module -> [Argument]
functionPointerParameters m = concatMap pointerParams (moduleDefinedFunctions m)
  where
    pointerParams = filter isPointer . functionParameters

testDescriptors = [ TestDescriptor { testPattern = ptPattern
                                   , testExpectedMapping = expectedMapper
                                   , testResultBuilder = extractSummary
                                   , testResultComparator = assertEqual
                                   }
                  ]

main :: IO ()
main = testAgainstExpected bcParser testDescriptors

