module Language.Ast
  ( Program(..)
  , Statement(..)
  , Block(..)
  , Element(..)
  , Application(..)
  , Func(..)
  , Loop(..)
  , Assignment(..)
  , Expression(..)
  , Variable(..)
  , Value(..)
  , If(..)
  , Identifier
  ) where

newtype Program =
  Program [Statement]
  deriving (Eq, Show)

data Statement
  = StLoop Loop
  | StAssign Assignment
  | StExpression Expression
  | StIf If
  | StFunc Func
  deriving (Eq, Show)

newtype Block =
  Block [Element]
  deriving (Eq, Show)

data Element
  = ElLoop Loop
  | ElAssign Assignment
  | ElExpression Expression
  | ElIf If
  deriving (Eq, Show)

data Application =
  Application Identifier
              [Expression]
              (Maybe Block)
  deriving (Eq, Show)

data Loop =
  Loop Expression
       (Maybe Identifier)
       Block
  deriving (Eq, Show)

data Assignment
  = AbsoluteAssignment Identifier
                       Expression
  | ConditionalAssignment Identifier
                          Expression
  deriving (Eq, Show)

data If =
  If Expression
     Block
     (Maybe Block)
  deriving (Eq, Show)

data Func =
  Func Identifier
       [Identifier]
       Block
  deriving (Eq, Show)

data Expression
  = EApp Application
  | BinaryOp String
             Expression
             Expression
  | UnaryOp String
            Expression
  | EVar Variable
  | EVal Value
  deriving (Eq, Show)

newtype Variable =
  Variable Identifier
  deriving (Eq, Show)

data Value
  = Number Float
  | Null
  | Symbol String
  | Lambda [Identifier]
           Block
  | BuiltIn Identifier
            [Identifier]
  deriving (Eq, Show)

type Identifier = String
