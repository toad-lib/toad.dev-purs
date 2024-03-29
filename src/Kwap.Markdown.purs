module Toad.Markdown where

import Prelude

import Control.Alternative ((<|>))
import Data.Array as Array
import Data.Array.NonEmpty as NEA
import Data.Foldable (fold, foldl)
import Data.Generic.Rep (class Generic)
import Data.Maybe (Maybe(..), maybe)
import Data.Show.Generic (genericShow)
import Data.String (trim)
import Data.String as String
import Data.String.NonEmpty as NES
import Data.String.NonEmpty.CodeUnits (fromNonEmptyCharArray)
import Data.Tuple (fst)
import Parsing (ParseState(..), Parser, getParserT)
import Parsing.Combinators
  ( advance
  , choice
  , lookAhead
  , many
  , many1Till_
  , notFollowedBy
  , optionMaybe
  , optional
  , try
  )
import Parsing.Combinators.Array as CombinatorArray
import Parsing.String (anyChar, anyTill, char, eof, string)
import Parsing.String.Basic (digit, lower)
import Toad.Concept as Concept

data Text
  = Unstyled String
  | Bold String
  | Italic String
  | BoldItalic String
  | InlineCode String

derive instance eqText :: Eq Text
derive instance genericText :: Generic Text _
instance showText :: Show Text where
  show = genericShow

textString :: Text -> String
textString (Unstyled s) = s
textString (Bold s) = s
textString (Italic s) = s
textString (BoldItalic s) = s
textString (InlineCode s) = s

data Anchor
  = Anchor (NEA.NonEmptyArray Text) String
  | ConceptAnchor (NEA.NonEmptyArray Text) Concept.Ident

derive instance eqAnchor :: Eq Anchor
derive instance genericAnchor :: Generic Anchor _
instance showAnchor :: Show Anchor where
  show = genericShow

anchorString :: Anchor -> String
anchorString (Anchor ts _) = fold (textString <$> ts)
anchorString (ConceptAnchor ts _) = fold (textString <$> ts)

data Token
  = AnchorToken Anchor
  | TextToken Text

derive instance eqToken :: Eq Token
derive instance genericToken :: Generic Token _
instance showToken :: Show Token where
  show (AnchorToken an) = "AnchorToken (" <> show an <> ")"
  show (TextToken text) = "TextToken (" <> show text <> ")"

tokenString :: Token -> String
tokenString (AnchorToken a) = anchorString a
tokenString (TextToken a) = textString a

tokenText :: Token -> Maybe Text
tokenText (TextToken t) = Just t
tokenText _ = Nothing

data Span = Span (NEA.NonEmptyArray Token)

derive instance eqSpan :: Eq Span
derive instance genericSpan :: Generic Span _
instance showSpan :: Show Span where
  show = genericShow

spanString :: Span -> String
spanString (Span ts) = fold (tokenString <$> ts)

data Heading
  = H1 Span
  | H2 Span
  | H3 Span
  | H4 Span
  | H5 Span
  | H6 Span

derive instance eqHeading :: Eq Heading
derive instance genericHeading :: Generic Heading _
instance showHeading :: Show Heading where
  show = genericShow

data CodeFenceFileType = CodeFenceFileType NES.NonEmptyString

derive instance eqCodeFenceFileType :: Eq CodeFenceFileType
derive instance genericCodeFenceFileType :: Generic CodeFenceFileType _
instance showCodeFenceFileType :: Show CodeFenceFileType where
  show = genericShow

data CodeFence = CodeFence (Maybe CodeFenceFileType) String

derive instance eqCodeFence :: Eq CodeFence
derive instance genericCodeFence :: Generic CodeFence _
instance showCodeFence :: Show CodeFence where
  show = genericShow

data ListToken
  = ListTokenSpan Span
  | ListTokenSpanSublist Span List

derive instance eqListToken :: Eq ListToken
instance showListToken :: Show ListToken where
  show (ListTokenSpan s) = "ListTokenSpan (" <> show s <> ")"
  show (ListTokenSpanSublist s l) = "ListTokenSpanSublist (" <> show s <> ") ("
    <> show l
    <> ")"

data List
  = OrderedList (NEA.NonEmptyArray ListToken)
  | UnorderedList (NEA.NonEmptyArray ListToken)

derive instance eqList :: Eq List
instance showList :: Show List where
  show (UnorderedList lts) = "UnorderedList (" <> show lts <> ")"
  show (OrderedList lts) = "OrderedList (" <> show lts <> ")"

data Element
  = ElementHeading Heading
  | ElementCodeFence CodeFence
  | ElementSpan Span
  | ElementList List
  | ElementComment String

derive instance eqElement :: Eq Element
derive instance genericElement :: Generic Element _
instance showElement :: Show Element where
  show = genericShow

newtype Document = Document (Array Element)

derive instance documentGeneric :: Generic Document _
derive newtype instance documentEq :: Eq Document
derive newtype instance documentSemi :: Semigroup Document
derive newtype instance documentMoid :: Monoid Document
instance showDocument :: Show Document where
  show = genericShow

elements :: Document -> Array Element
elements (Document a) = a

newtype Stop = Stop (Parser String String)

--| A boundary parser that should be respected as "this phrase has ended"
stop :: Stop -> Parser String String
stop (Stop p) = p

--| Universal markdown boundaries (eof / \n\n)
tokenStop :: Stop
tokenStop = Stop (choice [ eof <#> const "", string "\n\n" ])

--| Consume the input string until either the input stop or tokenStop is encountered
untilTokenStopOr :: Array Stop -> Parser String String
untilTokenStopOr others =
  choice (([ tokenStop ] <> others) <#> stop)
    # many1Till_ anyChar
    <#> (fst >>> NEA.fromFoldable1 >>> fromNonEmptyCharArray >>> NES.toString)

--| Unstyled text straight from textP will contain single characters
--|
--| this collapses them into an Unstyled string.
combineUnstyled
  :: ∀ a
   . (a -> Maybe Text)
  -> (Text -> a)
  -> NEA.NonEmptyArray a
  -> NEA.NonEmptyArray a
combineUnstyled text ofText tokens =
  let
    collapse soFar token = case [ text $ NEA.last soFar, text token ] of
      [ Just (Unstyled a), Just (Unstyled b) ] ->
        maybe
          (NEA.singleton $ ofText $ Unstyled $ a <> b)
          (_ <> (NEA.singleton $ ofText $ Unstyled $ a <> b))
          (NEA.init >>> NEA.fromArray $ soFar)
      _ -> soFar <> (NEA.singleton token)
  in
    foldl collapse (NEA.singleton $ NEA.head tokens) (NEA.tail tokens)

documentP :: Parser String Document
documentP = CombinatorArray.many elementP <#> Document

elementP :: Parser String Element
elementP = do
  _ <- many $ string "\n"
  (headingP <#> ElementHeading)
    <|> (listP <#> ElementList)
    <|> (codeFenceP <#> ElementCodeFence)
    <|> (commentP <#> ElementComment)
    <|> ((spanP []) <#> ElementSpan)

commentP :: Parser String String
commentP = do
  _ <- string "<!--"
  t <- untilTokenStopOr <<< pure <<< Stop $ string "-->"
  _ <- optional $ string "\n"
  pure <<< trim $ t

data Indentation = IndentSpaces Int

indentP :: Indentation -> Parser String Indentation
indentP i@(IndentSpaces n) = try $ do
  _ <- string $ String.joinWith "" $ Array.replicate n " "
  pure i

derive instance genericIndent :: Generic Indentation _
instance showIndent :: Show Indentation where
  show = genericShow

listRootIndentation :: Array Indentation
listRootIndentation = [ IndentSpaces 2, IndentSpaces 1 ]

listP_ :: Array Indentation -> Parser String List
listP_ is =
  let
    fromPartsListP
      :: forall a
       . Parser String a
      -> (NEA.NonEmptyArray ListToken -> List)
      -> Parser String List
    fromPartsListP pre l =
      l <$> CombinatorArray.many1 do
        (IndentSpaces spaces) <- choice $ map indentP is
        _ <- pre
        span <- spanP [ Stop $ string "\n" ]
        child <- optionMaybe
          (listP_ [ IndentSpaces (spaces + 3), IndentSpaces (spaces + 2) ])
        pure $
          case child of
            Just child' -> ListTokenSpanSublist span child'
            Nothing -> ListTokenSpan span
    olP = fromPartsListP
      ( choice [ CombinatorArray.many1 digit, CombinatorArray.many1 lower ] *>
          string ". "
      )
      OrderedList
    ulP = fromPartsListP (choice [ string "* ", string "- " ]) UnorderedList
  in
    ulP <|> olP

listP :: Parser String List
listP = listP_ listRootIndentation

codeFenceP :: Parser String CodeFence
codeFenceP = do
  _ <- many $ string "\n"
  _ <- string "```"
  fileType <- anyTill (string "\n") <#> fst
  contents <- anyTill (string "```") <#> fst <#> trim

  pure $ CodeFence (NES.fromString fileType <#> CodeFenceFileType) contents

headingP :: Parser String Heading
headingP =
  let
    h pre ctor = do
      _ <- string pre
      _ <- many (char ' ')
      spanP [ Stop $ string "\n" ] <#> ctor
  in
    h "######" H6
      <|> h "#####" H5
      <|> h "####" H4
      <|> h "###" H3
      <|> h "##" H2
      <|> h "#" H1

spanP :: Array Stop -> Parser String Span
spanP stops =
  many1Till_
    (tokenP stops)
    (choice $ [ tokenStop ] <> stops <#> stop)
    <#> (fst >>> NEA.fromFoldable1 >>> combineUnstyled tokenText TextToken >>> Span)

tokenP :: Array Stop -> Parser String Token
tokenP stops = (try anchorP <#> AnchorToken) <|>
  ((textP $ [ tokenStop ] <> stops) <#> TextToken)

anchorP :: Parser String Anchor
anchorP = do
  _ <- char '['
  label <-
    many1Till_
      (advance <<< textP <<< pure <<< Stop <<< lookAhead <<< string $ "]")
      (lookAhead <<< string $ "]")
      <#> fst
      <#> NEA.fromFoldable1
  _ <- char ']'
  _ <- many <<< char $ ' '
  _ <- char '('
  at <- optionMaybe <<< char $ '@'
  href <- untilTokenStopOr <<< pure <<< Stop <<< string $ ")"
  let text = combineUnstyled Just identity label
  pure $ maybe (Anchor text href)
    (const <<< ConceptAnchor text <<< Concept.Ident $ href)
    at

data Wrap
  = WrapStar1 -- *text*
  | WrapStar2 -- **text**
  | WrapStar3 -- ***text***
  | WrapStar2Under1 -- **_text_**
  | WrapUnder1Star2 -- _**text**_
  | WrapUnder1 -- _text_
  | WrapBacktick -- `text`

wrapOpen_ :: Wrap -> String
wrapOpen_ = case _ of
  WrapStar1 -> "*"
  WrapStar2 -> "**"
  WrapStar3 -> "***"
  WrapStar2Under1 -> "**_"
  WrapUnder1Star2 -> "_**"
  WrapUnder1 -> "_"
  WrapBacktick -> "`"

wrapClose_ :: Wrap -> String
wrapClose_ WrapStar2Under1 = "_**"
wrapClose_ WrapUnder1Star2 = "**_"
wrapClose_ symmetric = wrapOpen_ symmetric

wrapNotFollowedByStar :: Wrap -> Boolean
wrapNotFollowedByStar WrapStar1 = true
wrapNotFollowedByStar WrapStar2 = true
wrapNotFollowedByStar _ = false

wrapOpen :: Wrap -> Parser String Wrap
wrapOpen w
  | wrapNotFollowedByStar w =
      do
        _ <- string $ wrapOpen_ w
        _ <- notFollowedBy $ string "*"
        pure w
  | otherwise = do
      _ <- string $ wrapOpen_ w
      pure w

wrapClose :: Wrap -> Parser String Wrap
wrapClose w = do
  _ <- string $ wrapClose_ w
  pure w

textP :: Array Stop -> Parser String Text
textP stops =
  let
    stopOr :: forall a. Parser String a -> Parser String a
    stopOr p = do
      _ <- notFollowedBy $ choice $ stops <#> stop
      p

    textP' :: forall a. (String -> a) -> Array Wrap -> Parser String a
    textP' t ws = try $ stopOr do
      wrap <- choice $ ws <#> wrapOpen
      s <- untilTokenStopOr $ stops <>
        [ Stop $ map (const "") (wrapClose wrap) ]
      pure $ t s
  in
    choice
      [ textP' InlineCode [ WrapBacktick ]
      , textP' BoldItalic [ WrapStar3, WrapStar2Under1, WrapUnder1Star2 ]
      , textP' Italic [ WrapStar1, WrapUnder1 ]
      , textP' Bold [ WrapStar2 ]
      , stopOr anyChar
          <#> NEA.singleton
          <#> fromNonEmptyCharArray
          <#> NES.toString
          <#> Unstyled
      ]
