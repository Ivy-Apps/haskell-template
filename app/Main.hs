module Main where

main :: IO ()
main = do
    putStrLn "Hello, Haskell!"
    putStrLn . show $ x

x :: Integer
x = 5
