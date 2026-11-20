module Main (main) where
import Data.Char (isAlphaNum, isDigit)
import Data.List (isPrefixOf, nub)

main :: IO ()
main = do
  core <- readFile "build/model/MAlonzo/Code/ClientCore.hs"
  model <- readFile "build/model/MAlonzo/Code/ClientModel.hs"
  template <- readFile "scripts/ClientOracle.template.hs"
  let tokens = nub . words . map (\c -> if isAlphaNum c || c=='_' then c else ' ')
      declarations [] = []
      declarations (line:rest)
        | "data " `isPrefixOf` line = line:takeWhile (not . isPrefixOf "--") rest <>
            declarations (dropWhile (not . isPrefixOf "--") rest)
        | otherwise = declarations rest
      ownSymbols prefix source = case prefix of
        "T_" -> [words line!!1 | line <- lines source,"data T_" `isPrefixOf` line]
        "C_" -> tokens (unlines (declarations (lines source)))
        _ -> nub [head (words line) | line <- lines source,"d_" `isPrefixOf` line]
      symbol prefix name source = case [t | t <- ownSymbols prefix source,
            let start=prefix<>name<>"_", start `isPrefixOf` t,
            not (null (drop (length start) t)), all isDigit (drop (length start) t)] of
        [found] -> found
        matches -> error ("Expected one generated symbol for "<>name<>", found "<>show matches)
      emit [] = []
      emit ('@':rest) = case break (=='@') rest of
        (key,'@':tail') ->
          let (kind,_:name)=break (=='.') key
              (prefix,source)=case kind of
                "Type" -> ("T_",core)
                "Ctor" -> ("C_",core)
                "Model" -> ("C_",model)
                "Fun" -> ("d_",model)
                _ -> error ("Unknown symbol class "<>kind)
           in symbol prefix name source<>emit tail'
        _ -> error "Unclosed template token"
      emit (c:rest) = c:emit rest
  writeFile "build/model/ClientOracle.hs" (emit template)
