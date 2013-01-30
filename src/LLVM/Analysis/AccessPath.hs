{-# LANGUAGE DeriveDataTypeable, FlexibleContexts, DeriveGeneric #-}
{-# LANGUAGE ViewPatterns #-}
-- | This module defines an abstraction over field accesses of
-- structures called AccessPaths.  A concrete access path is rooted at
-- a value, while an abstract access path is rooted at a type.  Both
-- include a list of 'AccessType's that denote dereferences of
-- pointers, field accesses, and array references.
module LLVM.Analysis.AccessPath (
  -- * Types
  AccessPath(..),
  AbstractAccessPath(..),
  AccessType(..),
  AccessPathError,
  -- * Constructor
  accessPath,
  abstractAccessPath,
  appendAccessPath,
  followAccessPath,
  reduceAccessPath,
  externalizeAccessPath
  ) where

import Control.DeepSeq
import Control.Exception
import Control.Failure hiding ( failure )
import qualified Control.Failure as F
import Data.Hashable
import Data.List ( foldl' )
import Data.Typeable
import Text.PrettyPrint.GenericPretty

import LLVM.Analysis

-- import Text.Printf
-- import Debug.Trace
-- debug = flip trace

data AccessPathError = NoPathError Value
                     | NotMemoryInstruction Instruction
                     | CannotFollowPath AbstractAccessPath Value
                     | BaseTypeMismatch Type Type
                     | NonConstantInPath AbstractAccessPath Value
                     | EndpointTypeMismatch Type Type
                     | IrreducableAccessPath AbstractAccessPath
                     | CannotExternalizeType Type
                     deriving (Typeable, Show)

instance Exception AccessPathError

-- | The sequence of field accesses used to reference a field
-- structure.
data AbstractAccessPath =
  AbstractAccessPath { abstractAccessPathBaseType :: Type
                     , abstractAccessPathEndType :: Type
                     , abstractAccessPathComponents :: [(Type, AccessType)]
                     }
  deriving (Eq, Ord, Generic)

instance Out AbstractAccessPath
instance Show AbstractAccessPath where
  show = pretty

instance Hashable AbstractAccessPath where
  hashWithSalt s (AbstractAccessPath bt et cs) =
    s `hashWithSalt` bt `hashWithSalt` et `hashWithSalt` cs

appendAccessPath :: (Failure AccessPathError m)
                    => AbstractAccessPath
                    -> AbstractAccessPath
                    -> m AbstractAccessPath
appendAccessPath (AbstractAccessPath bt1 et1 cs1) (AbstractAccessPath bt2 et2 cs2) =
  case et1 == bt2 of
    True -> return $ AbstractAccessPath bt1 et2 (cs1 ++ cs2)
    False -> F.failure $ EndpointTypeMismatch et1 bt2

-- | If the access path has more than one field access component, take
-- the first field access and the base type to compute a new base type
-- (the type of the indicated field) and the rest of the path
-- components.  Also allows for the discarding of array accesses.
--
-- Each call reduces the access path by one component
reduceAccessPath :: (Failure AccessPathError m)
                    => AbstractAccessPath -> m AbstractAccessPath
reduceAccessPath (AbstractAccessPath (TypePointer t _) et ((_, AccessDeref):cs)) =
  return $! AbstractAccessPath t et cs
-- FIXME: Some times (e.g., pixmap), the field number is out of range.
-- Have to figure out what could possibly cause that. Until then, just
-- ignore those cases.  Users of this are working at best-effort anyway.
reduceAccessPath p@(AbstractAccessPath (TypeStruct _ ts _) et ((_,AccessField fldNo):cs)) =
  case fldNo < length ts of
    True -> return $! AbstractAccessPath (ts !! fldNo) et cs
    False -> F.failure $ IrreducableAccessPath p
reduceAccessPath (AbstractAccessPath (TypeArray _ t) et ((_,AccessArray):cs)) =
  return $! AbstractAccessPath t et cs
reduceAccessPath p = F.failure $ IrreducableAccessPath p

instance NFData AbstractAccessPath where
  rnf a@(AbstractAccessPath _ _ ts) = ts `deepseq` a `seq` ()

data AccessPath =
  AccessPath { accessPathBaseValue :: Value
             , accessPathEndType :: Type
             , accessPathComponents :: [(Type, AccessType)]
             }
  deriving (Generic, Eq, Ord)

instance Out AccessPath
instance Show AccessPath where
  show = pretty

instance NFData AccessPath where
  rnf a@(AccessPath _ _ ts) = ts `deepseq` a `seq` ()

instance Hashable AccessPath where
  hashWithSalt s (AccessPath bv ev cs) =
    s `hashWithSalt` bv `hashWithSalt` ev `hashWithSalt` cs

data AccessType = AccessField !Int
                | AccessArray
                | AccessDeref
                deriving (Read, Show, Eq, Ord, Generic)

instance Out AccessType

instance NFData AccessType where
  rnf a@(AccessField i) = i `seq` a `seq` ()
  rnf _ = ()

instance Hashable AccessType where
  hashWithSalt s (AccessField ix) =
    s `hashWithSalt` (1 :: Int) `hashWithSalt` ix
  hashWithSalt s AccessArray = s `hashWithSalt` (26 :: Int)
  hashWithSalt s AccessDeref = s `hashWithSalt` (300 :: Int)

followAccessPath :: (Failure AccessPathError m) => AbstractAccessPath -> Value -> m Value
followAccessPath aap@(AbstractAccessPath bt _ components) val =
  case derefPointerType bt /= valueType val of
    True -> F.failure (BaseTypeMismatch bt (valueType val))
    False -> walk components val
  where
    walk [] v = return v
    walk ((_, AccessField ix) : rest) v =
      case valueContent' v of
        ConstantC ConstantStruct { constantStructValues = vs } ->
          case ix < length vs of
            False -> error $ concat [ "LLVM.Analysis.AccessPath.followAccessPath.walk: "
                                    ," Invalid access path: ", show aap, " / ", show val
                                    ]
            True -> walk rest (vs !! ix)
        _ -> F.failure (NonConstantInPath aap val)
    walk _ _ = F.failure (CannotFollowPath aap val)

abstractAccessPath :: AccessPath -> AbstractAccessPath
abstractAccessPath (AccessPath v t p) =
  AbstractAccessPath (valueType v) t p

-- | For Store, RMW, and CmpXchg instructions, the returned access
-- path describes the field /stored to/.  For Load instructions, the
-- returned access path describes the field loaded.  For
-- GetElementPtrInsts, the returned access path describes the field
-- whose address was taken/computed.
accessPath :: (Failure AccessPathError m) => Instruction -> m AccessPath
accessPath i =
  case i of
    StoreInst { storeAddress = sa, storeValue = sv } ->
      return $! go (AccessPath sa (valueType sv) []) sa
    LoadInst { loadAddress = la } ->
      return $! go (AccessPath la (valueType i) []) la
    AtomicCmpXchgInst { atomicCmpXchgPointer = p
                      , atomicCmpXchgNewValue = nv
                      } ->
      return $! go (AccessPath p (valueType nv) []) p
    AtomicRMWInst { atomicRMWPointer = p
                  , atomicRMWValue = v
                  } ->
      return $! go (AccessPath p (valueType v) []) p
    GetElementPtrInst {} ->
      return $! go (AccessPath (toValue i) (valueType i) []) (toValue i)
    _ -> F.failure (NotMemoryInstruction i)
  where
    go p v =
      case valueContent' v of
        InstructionC GetElementPtrInst { getElementPtrValue = (valueContent' -> InstructionC LoadInst { loadAddress = la })
                                       , getElementPtrIndices = [_]
                                       } ->
          let p' = p { accessPathBaseValue = la
                     , accessPathComponents = (valueType v, AccessArray) : accessPathComponents p
                     }
          in go p' la
        InstructionC GetElementPtrInst { getElementPtrValue = base
                                       , getElementPtrIndices = [_]
                                       } ->
          let p' = p { accessPathBaseValue = base
                     , accessPathComponents = (valueType v, AccessArray) : accessPathComponents p
                     }
          in go p' base
        InstructionC GetElementPtrInst { getElementPtrValue = base@(valueContent' -> InstructionC LoadInst { loadAddress = la })
                                       , getElementPtrIndices = ixs
                                       } ->
          -- Note we need to pass the un-casted base to gepIndexFold
          -- so that it computes its types properly.  If we give it
          -- the value with the bitcast stripped off, it will just
          -- look like a random pointer (instead of a pointer to a
          -- struct).
          let p' = p { accessPathBaseValue = la
                     , accessPathComponents =
                       gepIndexFold base ixs ++ accessPathComponents p
                     }
          in go p' la
        InstructionC GetElementPtrInst { getElementPtrValue = base
                                       , getElementPtrIndices = ixs
                                       } ->
          let p' = p { accessPathBaseValue = base
                     , accessPathComponents =
                       gepIndexFold base ixs ++ accessPathComponents p
                     }
          in go p' base
        ConstantC ConstantValue { constantInstruction =
          GetElementPtrInst { getElementPtrValue = base
                            , getElementPtrIndices = ixs
                            } } ->
          let p' = p { accessPathBaseValue = base
                     , accessPathComponents =
                       gepIndexFold base ixs ++ accessPathComponents p
                     }
          in go p' base
        InstructionC LoadInst { loadAddress = la } ->
          let p' = p { accessPathBaseValue  = la
                     , accessPathComponents =
                          (valueType v, AccessDeref) : accessPathComponents p
                     }
          in go p' la
        _ -> p { accessPathBaseValue = v }

-- | Convert an 'AbstractAccessPath' to a format that can be written
-- to disk and read back into another process.  The format is the pair
-- of the base name of the structure field being accessed (with
-- struct. stripped off) and with any numeric suffixes (which are
-- added by llvm) chopped off.  The actually list of 'AccessType's is
-- preserved.
--
-- The struct name mangling here basically assumes that the types
-- exposed via the access path abstraction have the same definition in
-- all compilation units.  Ensuring this between runs is basically
-- impossible, but it is pretty much always the case.
externalizeAccessPath :: (Failure AccessPathError m)
                         => AbstractAccessPath
                         -> m (String, [AccessType])
externalizeAccessPath accPath =
  maybe (F.failure (CannotExternalizeType bt)) return $ do
    baseName <- structTypeToName (stripPointerTypes bt)
    return (baseName, map snd $ abstractAccessPathComponents accPath)
  where
    bt = abstractAccessPathBaseType accPath

-- Internal Helpers


derefPointerType :: Type -> Type
derefPointerType (TypePointer p _) = p
derefPointerType t = error ("LLVM.Analysis.AccessPath.derefPointerType: Type is not a pointer type: " ++ show t)

gepIndexFold :: Value -> [Value] -> [(Type, AccessType)]
gepIndexFold base indices@(ptrIx : ixs) =
  -- GEPs always have a pointer as the base operand
  let ty@(TypePointer baseType _) = valueType base
  in case valueContent ptrIx of
    ConstantC ConstantInt { constantIntValue = 0 } ->
      snd $ foldl' walkGep (baseType, []) ixs
    _ ->
      snd $ foldl' walkGep (baseType, [(ty, AccessArray)]) ixs
  where
    walkGep (ty, acc) ix =
      case ty of
        -- If the current type is a pointer, this must be an array
        -- access; that said, this wouldn't even be allowed because a
        -- pointer would have to go through a Load...  check this
        TypePointer ty' _ -> (ty', (ty, AccessArray) : acc)
        TypeArray _ ty' -> (ty', (ty, AccessArray) : acc)
        TypeStruct _ ts _ ->
          case valueContent ix of
            ConstantC ConstantInt { constantIntValue = fldNo } ->
              let fieldNumber = fromIntegral fldNo
                  ty' = ts !! fieldNumber
              in (ty', (ty', AccessField fieldNumber) : acc)
            _ -> error ("LLVM.Analysis.AccessPath.gepIndexFold.walkGep: Invalid non-constant GEP index for struct: " ++ show ty)
        _ -> error ("LLVM.Analysis.AccessPath.gepIndexFold.walkGep: Unexpected type in GEP: " ++ show ty)
gepIndexFold v [] =
  error ("LLVM.Analysis.AccessPath.gepIndexFold: GEP instruction/base with empty index list: " ++ show v)

{-# ANN module "HLint: ignore Use if" #-}