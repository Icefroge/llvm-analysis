module Data.LLVM.Private.PlaceholderTypes ( Identifier(..)
                                          , Instruction(..)
                                          , InstructionT(..)
                                          , Constant(..)
                                          , ConstantT(..)
                                          , ArithFlag(..)
                                          , ExternalDecl(..)
                                          , NamedType(..)
                                          , GlobalDeclaration(..)
                                          , PartialConstant
                                          , voidInst
                                          , namedInst
                                          , maybeNamedInst
                                          , valueRef
                                          ) where

import Data.ByteString.Lazy (ByteString)
import Data.LLVM.Private.AttributeTypes

-- These types are generated by the parser and will be
-- *temporary*.  They reference strings since that is all we have at
-- parse time.  These types will be replaced by direct references
-- after the entire AST is built and we can build the self-referential
-- graph structure.

data Identifier = LocalIdentifier ByteString
                | GlobalIdentifier ByteString
                | DebugIdentifier ByteString
                  deriving (Show, Eq)

data Instruction = Instruction { instName :: Maybe Identifier
                               , instType :: Type
                               , instContent :: InstructionT
                               }
                   -- This variant is used if we can't build the type
                   -- yet.  It can be resolved after everything is
                   -- made properly referential.  This is useful for
                   -- getelementptr and extractvalue.
                 | UnresolvedInst { unresInstName :: Maybe Identifier
                                  , unresInstContent :: InstructionT
                                  }
           deriving (Show)

type PartialConstant = Type -> Constant

voidInst :: InstructionT -> Instruction
voidInst v = Instruction { instName = Nothing
                         , instType = TypeVoid
                         , instContent = v
                         }

namedInst :: Identifier -> Type -> InstructionT -> Instruction
namedInst i t v = Instruction { instName = Just i
                              , instType = t
                              , instContent = v
                              }

maybeNamedInst :: Maybe Identifier -> Type -> InstructionT -> Instruction
maybeNamedInst i t v = Instruction { instName = i
                                   , instType = t
                                   , instContent = v
                                   }

data Constant = ConstValue ConstantT Type
              | ValueRef Identifier
              deriving (Show, Eq)

valueRef ident = const (ValueRef ident)

-- The first group of value types are unusual and are *not* "users".
-- This distinction is not particularly important for my purposes,
-- though, so I'm just giving all values a list of operands (which
-- will be empty for these things)
data InstructionT = InlineAsm ByteString ByteString -- ASM String, Constraint String; can parse constraints still
            | RetInst (Maybe Constant)
            | UnconditionalBranchInst ByteString
            | BranchInst Constant ByteString ByteString
            | SwitchInst Constant ByteString [(Constant, ByteString)]
            | IndirectBranchInst Constant [Constant]
            | UnwindInst
            | UnreachableInst
            | AddInst [ArithFlag] Constant Constant
            | SubInst [ArithFlag] Constant Constant
            | MulInst [ArithFlag] Constant Constant
            | DivInst Constant Constant -- Does not encode the exact flag of sdiv.  Convince me to
            | RemInst Constant Constant
            | ShlInst Constant Constant
            | LshrInst Constant Constant
            | AshrInst Constant Constant
            | AndInst Constant Constant
            | OrInst Constant Constant
            | XorInst Constant Constant
            | ExtractElementInst Constant Constant
            | InsertElementInst Constant Constant Constant
            | ShuffleVectorInst Constant Constant Constant
            | ExtractValueInst Constant [Integer]
            | InsertValueInst Constant Constant Integer
            | AllocaInst Type Constant Integer -- Type, NumElems, align
            | LoadInst Bool Constant Integer -- Volatile? Type Dest align
            | StoreInst Bool Constant Constant Integer -- Volatile? Type Dest align
            | TruncInst Constant Type -- The value being truncated, and the type truncted to
            | ZExtInst Constant Type
            | SExtInst Constant Type
            | FPTruncInst Constant Type
            | FPExtInst Constant Type
            | FPToUIInst Constant Type
            | FPToSIInst Constant Type
            | UIToFPInst Constant Type
            | SIToFPInst Constant Type
            | PtrToIntInst Constant Type
            | IntToPtrInst Constant Type
            | BitcastInst Constant Type
            | ICmpInst ICmpCondition Constant Constant
            | FCmpInst FCmpCondition Constant Constant
            | PhiNode [(Constant, Identifier)]
            | SelectInst Constant Constant Constant
            | GetElementPtrInst Bool Constant [Constant]
            | CallInst { callIsTail :: Bool
                       , callConvention :: CallingConvention
                       , callParamAttrs :: [ParamAttribute]
                       , callRetType :: Type
                       , callFunction :: Constant
                       , callArguments :: [Constant]
                       , callAttrs :: [FunctionAttribute]
                       }
            | InvokeInst { invokeConvention :: CallingConvention
                         , invokeParamAttrs :: [ParamAttribute]
                         , invokeRetType :: Type
                         , invokeFunction :: Constant
                         , invokeArguments :: [Constant]
                         , invokeAttrs :: [FunctionAttribute]
                         , invokeNormalLabel :: Constant
                         , invokeUnwindLabel :: Constant
                         }
            | VaArgInst Constant Type
            deriving (Show)

data ArithFlag = AFNSW | AFNUW deriving (Show)
data ExternalDecl = ExternalDecl Type Identifier
                    deriving (Show, Eq)

data NamedType = NamedType Identifier Type
                 deriving (Show, Eq)

-- Ident AddrSpace Annotations Type(aptr) Initializer alignment
data GlobalDeclaration = GlobalDeclaration Identifier Int [GlobalAnnotation] Type Constant Integer
                         deriving (Show, Eq)

-- FIXME: Convert the second ident to a Value (basic blocks are values)
data ConstantT = BlockAddress Identifier Identifier -- Func Ident, Block Label -- to be resolved into something useful later
               | ConstantAggregateZero
               | ConstantArray [Constant] -- This should have some parameters but I don't know what
               | ConstantExpr Constant -- change this to something else maybe?  Value should suffice... might even eliminate this one
               | ConstantFP Double
               | ConstantInt Integer
               | ConstantPointerNull
               | ConstantStruct [Constant] -- Just a list of other constants
               | ConstantVector [Constant] -- again
               | UndefValue
               | MDNode [Constant] -- A list of constants (and other metadata)
               | MDString ByteString
--               | Function [Value] [FunctionAttribute] [ValueT] -- Arguments, function attrs, block list
               | GlobalVariable VisibilityStyle LinkageType ByteString
--               | GlobalAlias VisibilityStyle LinkageType ByteString Value -- new name, real var
               -- | ConstantIdentifier Identifier -- Wrapper for globals - to be resolved later into a more useful direct references to a GlobalVariable
               deriving (Show, Eq)
