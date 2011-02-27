module Data.LLVM.Private.Parser.Attributes ( paramAttribute
                                           , functionAttribute
                                           , visibilityStyle
                                           , linkageType
                                           , callingConvention
                                           , gcName
                                           , sectionName
                                           , addrSpace
                                           , globalAnnotation
                                           , globalIdentifierP
                                           , localIdentifierP
                                           , metadataIdentifierP
                                           , identifier
                                           , instructionMetadata
                                           , branchTarget
                                           , inBoundsP
                                           , icmpConditionP
                                           , fcmpConditionP
                                           , volatileFlag
                                           , alignmentSpec
                                           , functionAlignment
                                           , addInst
                                           , subInst
                                           , mulInst
                                           , divInst
                                           , remInst
                                           , arithFlag
                                           ) where

import Control.Applicative hiding ((<|>))
import Data.Text (Text)
import Text.Parsec

import Data.LLVM.Private.AttributeTypes
import Data.LLVM.Private.Lexer
import Data.LLVM.Private.PlaceholderTypes
import Data.LLVM.Private.Parser.Primitive


paramAttribute :: AssemblyParser ParamAttribute
paramAttribute = tokenAs matcher
  where matcher x =
          case x of
            TPAZeroExt -> Just PAZeroExt
            TPASignExt -> Just PASignExt
            TPAInReg -> Just PAInReg
            TPAByVal -> Just PAByVal
            TPASRet -> Just PASRet
            TPANoAlias -> Just PANoAlias
            TPANoCapture -> Just PANoCapture
            TPANest -> Just PANest
            _ -> Nothing

functionAttribute :: AssemblyParser FunctionAttribute
functionAttribute = tokenAs matcher
  where matcher x =
          case x of
            TFAAlignStack a -> Just $ FAAlignStack a
            TFAAlwaysInline -> Just FAAlwaysInline
            TFAHotPatch -> Just FAHotPatch
            TFAInlineHint -> Just FAInlineHint
            TFANaked -> Just FANaked
            TFANoImplicitFloat -> Just FANoImplicitFloat
            TFANoInline -> Just FANoInline
            TFANoRedZone -> Just FANoRedZone
            TFANoReturn -> Just FANoReturn
            TFANoUnwind -> Just FANoUnwind
            TFAOptSize -> Just FAOptSize
            TFAReadNone -> Just FAReadNone
            TFAReadOnly -> Just FAReadOnly
            TFASSP -> Just FASSP
            TFASSPReq -> Just FASSPReq
            _ -> Nothing

visibilityStyle :: AssemblyParser VisibilityStyle
visibilityStyle = tokenAs matcher
  where matcher x =
          case x of
            TVisDefault -> Just VisibilityDefault
            TVisHidden -> Just VisibilityHidden
            TVisProtected -> Just VisibilityProtected
            _ -> Just VisibilityDefault

linkageType :: AssemblyParser LinkageType
linkageType = tokenAs matcher
  where matcher x =
          case x of
            TPrivate -> Just LTPrivate
            TLinkerPrivate -> Just LTLinkerPrivate
            TLinkerPrivateWeak -> Just LTLinkerPrivateWeak
            TLinkerPrivateWeakDefAuto -> Just LTLinkerPrivateWeakDefAuto
            TInternal -> Just LTInternal
            TAvailableExternally -> Just LTAvailableExternally
            TLinkOnce -> Just LTLinkOnce
            TWeak -> Just LTWeak
            TCommon -> Just LTCommon
            TAppending -> Just LTAppending
            TExternWeak -> Just LTExternWeak
            TLinkOnceODR -> Just LTLinkOnceODR
            TWeakODR -> Just LTWeakODR
            TDLLImport -> Just LTDLLImport
            TDLLExport -> Just LTDLLExport
            _ -> Just LTExtern


callingConvention :: AssemblyParser CallingConvention
callingConvention = tokenAs matcher
  where matcher x =
          case x of
            TCCN n -> Just (CCN n)
            TCCCCC -> Just CCC
            TCCFastCC -> Just CCFastCC
            TCCColdCC -> Just CCColdCC
            TCCGHC -> Just CCGHC
            _ -> Just CCC

gcName :: AssemblyParser GCName
gcName = consumeToken TGC >> (GCName <$> parseString)

sectionName :: AssemblyParser (Maybe Text)
sectionName = option Nothing p
  where p = Just <$> parseString

addrSpace :: AssemblyParser Int
addrSpace = option 0 (tokenAs matcher)
  where matcher x =
          case x of
            TAddrspace n -> Just n
            _ -> Nothing

globalAnnotation :: AssemblyParser GlobalAnnotation
globalAnnotation = tokenAs matcher
  where matcher x =
          case x of
            TConstant -> Just GAConstant
            TGlobal -> Just GAGlobal
            _ -> Nothing

globalIdentifierP :: AssemblyParser Identifier
globalIdentifierP = tokenAs matcher
  where matcher x =
          case x of
            TGlobalIdent i -> Just (makeGlobalIdentifier i)
            _ -> Nothing

localIdentifierP :: AssemblyParser Identifier
localIdentifierP = tokenAs matcher
  where matcher x =
          case x of
            TLocalIdent i -> Just (makeLocalIdentifier i)
            _ -> Nothing

metadataIdentifierP :: AssemblyParser Identifier
metadataIdentifierP = tokenAs matcher
  where matcher x =
          case x of
            TMetadataName i -> Just (makeMetaIdentifier i)
            _ -> Nothing

-- | Combined form which can match any identifier with just one
-- pattern match (no choice combinator required)
identifier :: AssemblyParser Identifier
identifier = tokenAs matcher
  where matcher x =
          case x of
            TGlobalIdent i -> Just (makeGlobalIdentifier i)
            TLocalIdent i -> Just (makeLocalIdentifier i)
            TMetadataName i -> Just (makeMetaIdentifier i)
            _ -> Nothing

instructionMetadata :: AssemblyParser Identifier
instructionMetadata = consumeToken TDbg >> metadataIdentifierP

branchTarget :: AssemblyParser Constant
branchTarget = ValueRef <$> localIdentifierP

inBoundsP :: AssemblyParser Bool
inBoundsP = tokenAs matcher
  where matcher x =
          case x of
            TInbounds -> Just True
            _ -> Just False

icmpConditionP :: AssemblyParser ICmpCondition
icmpConditionP = tokenAs matcher
  where matcher x =
          case x of
            Teq -> Just ICmpEq
            Tne -> Just ICmpNe
            Tugt -> Just ICmpUgt
            Tuge -> Just ICmpUge
            Tult -> Just ICmpUlt
            Tule -> Just ICmpUle
            Tsgt -> Just ICmpSgt
            Tsge -> Just ICmpSge
            Tslt -> Just ICmpSlt
            Tsle -> Just ICmpSle
            _ -> Nothing

fcmpConditionP :: AssemblyParser FCmpCondition
fcmpConditionP = tokenAs matcher
  where matcher x =
          case x of
            TFalseLit -> Just FCmpFalse
            Toeq -> Just FCmpOeq
            Togt -> Just FCmpOgt
            Toge -> Just FCmpOge
            Tolt -> Just FCmpOlt
            Tole -> Just FCmpOle
            Tone -> Just FCmpOne
            Tord -> Just FCmpOrd
            Tueq -> Just FCmpUeq
            Tugt -> Just FCmpUgt
            Tuge -> Just FCmpUge
            Tult -> Just FCmpUlt
            Tule -> Just FCmpUle
            Tune -> Just FCmpUne
            Tuno -> Just FCmpUno
            TTrueLit -> Just FCmpTrue
            _ -> Nothing

volatileFlag :: AssemblyParser Bool
volatileFlag = tokenAs matcher
  where matcher x =
          case x of
            TVolatile -> Just True
            _ -> Just False

-- | Parse ", align N" and return N.  Defaults to 0 if not specified.
alignmentSpec :: AssemblyParser Integer
alignmentSpec = option 0 (consumeToken TComma *> basicAlignmentSpec)

functionAlignment :: AssemblyParser Integer
functionAlignment = basicAlignmentSpec

basicAlignmentSpec :: AssemblyParser Integer
basicAlignmentSpec = consumeToken TAlign *> tokenAs matcher
  where matcher x =
          case x of
            TIntLit i -> Just i
            _ -> Nothing

addInst :: AssemblyParser ()
addInst = tokenAs matcher
  where matcher x =
          case x of
            TAdd -> Just ()
            TFadd -> Just ()
            _ -> Nothing

subInst :: AssemblyParser ()
subInst = tokenAs matcher
  where matcher x =
          case x of
            TSub -> Just ()
            TFsub -> Just ()
            _ -> Nothing

mulInst :: AssemblyParser ()
mulInst = tokenAs matcher
  where matcher x =
          case x of
            TMul -> Just ()
            TFmul -> Just ()
            _ -> Nothing

divInst :: AssemblyParser ()
divInst = tokenAs matcher
  where matcher x =
          case x of
            TUdiv -> Just ()
            TSdiv -> Just ()
            TFdiv -> Just ()
            _ -> Nothing

remInst :: AssemblyParser ()
remInst = tokenAs matcher
  where matcher x =
          case x of
            TUrem -> Just ()
            TSrem -> Just ()
            TFrem -> Just ()
            _ -> Nothing

arithFlag :: AssemblyParser ArithFlag
arithFlag = tokenAs matcher
  where matcher x =
          case x of
            TNSW -> Just AFNSW
            TNUW -> Just AFNUW
            _ -> Nothing