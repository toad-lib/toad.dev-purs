module Kwap.Concept
  ( Manifest(..)
  , Decl(..)
  , decls
  , declOfRecord
  , pathString
  , aliasString
  , titleString
  , path
  , alias
  , title
  , Path(..)
  , Alias(..)
  , Title(..)
  ) where

import Prelude

import Data.Maybe (Maybe, fromMaybe)

newtype Alias = Alias String

derive newtype instance showAlias :: Show Alias
derive newtype instance eqAlias :: Eq Alias
derive newtype instance ordAlias :: Ord Alias
derive newtype instance semiAlias :: Semigroup Alias
derive newtype instance monoidAlias :: Monoid Alias

aliasString :: Alias -> String
aliasString (Alias s) = s

newtype Path = Path String

derive newtype instance showPath :: Show Path
derive newtype instance eqPath :: Eq Path
derive newtype instance ordPath :: Ord Path
derive newtype instance semiPath :: Semigroup Path
derive newtype instance monoidPath :: Monoid Path

pathString :: Path -> String
pathString (Path s) = s

newtype Title = Title String

derive newtype instance showTitle :: Show Title
derive newtype instance eqTitle :: Eq Title
derive newtype instance ordTitle :: Ord Title
derive newtype instance semiTitle :: Semigroup Title
derive newtype instance monoidTitle :: Monoid Title

titleString :: Title -> String
titleString (Title s) = s

newtype Decl = Decl
  { path :: Path
  , title :: Title
  , alias :: Maybe Alias
  }

derive newtype instance eqOne :: Eq Decl
derive newtype instance showOne :: Show Decl

declOfRecord
  :: { path :: String, title :: String, alias :: Maybe String } -> Decl
declOfRecord { path: p, title: t, alias: a } = Decl
  { path: Path p, title: Title t, alias: Alias <$> a }

path :: Decl -> Path
path (Decl { path: p }) = p

title :: Decl -> Title
title (Decl { title: t }) = t

alias :: Decl -> Alias
alias (Decl { path: (Path p), alias: a }) = fromMaybe (Alias p) a

newtype Manifest = Manifest (Array Decl)

derive newtype instance eqManifest :: Eq Manifest
derive newtype instance showManifest :: Show Manifest

decls :: Manifest -> Array Decl
decls (Manifest a) = a