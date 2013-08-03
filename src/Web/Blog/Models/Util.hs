
module Web.Blog.Models.Util  where

import Control.Monad.IO.Class                (liftIO)
import Control.Monad.Loops                   (firstM)
import Data.Char                             (isAlphaNum)
import Data.Maybe                            (isNothing, fromJust)
import Data.Time                             (getCurrentTime)
import Web.Blog.Models
import qualified Data.Text                   as T
import qualified Database.Persist.Postgresql as D

slugLength :: Int
slugLength = 10

insertEntry :: Entry -> D.SqlPersistM (D.Key Entry)
insertEntry entry = do
  slugText <- genSlug slugLength (entryTitle entry)
  entryKey <- D.insert entry
  D.insert_ $ Slug entryKey slugText True
  return entryKey

genSlug' :: Int -> T.Text -> T.Text
genSlug' w = squash . T.dropAround isDash . T.map replaceSymbols . T.toCaseFold
  where
    isDash = (==) '-'
    replaceSymbols s =
      if isAlphaNum s
        then
          s
        else
          '-'
    squash = T.intercalate "-" . take w . filter (not . T.null) . T.split isDash

-- TODO: Maybe include date in slug?
genSlug :: Int -> T.Text -> D.SqlPersistM T.Text
genSlug w t = do
  let
    baseSlug = genSlug' w t
  base <- D.getBy $ UniqueSlug baseSlug
  case base of
    Just _ -> do
      freshSlug <- firstM isFresh $
        map (T.append baseSlug . T.pack . show) ([-2,-3..] :: [Integer])
      return $ fromJust freshSlug
    Nothing ->
      return baseSlug
  where
    isFresh :: T.Text -> D.SqlPersistM Bool
    isFresh s = do
      found <- D.getBy $ UniqueSlug s
      return $ isNothing found

-- TODO: separate changeSlug function to be able to re-double back on old
-- names


postedEntries :: [D.SelectOpt Entry] -> D.SqlPersistM [D.Entity Entry]
postedEntries opts = do
  now <- liftIO getCurrentTime
  D.selectList [ EntryPostedAt D.<=. now ] opts

getCurrentSlug :: D.Entity Entry -> D.SqlPersistM (Maybe (D.Entity Slug))
getCurrentSlug entry = D.selectFirst [ SlugEntryId   D.==. eKey
                                   , SlugIsCurrent D.==. True ] []
  where
    D.Entity eKey _ = entry

getUrlPath :: D.Entity Entry -> D.SqlPersistM T.Text
getUrlPath entry = do
  slug <- getCurrentSlug entry
  case slug of
    Just (D.Entity _ slug') ->
      return $ T.append "/entry/" (slugSlug slug')
    Nothing               -> do
      let
        D.Entity eKey _ = entry
      return $ T.append "/entry/id/" (T.pack $ show eKey)


getTags :: D.Entity Entry -> D.SqlPersistM [Tag]
getTags entry = getTagsByEntityKey $ D.entityKey entry

getTagsByEntityKey :: D.Key Entry -> D.SqlPersistM [Tag]
getTagsByEntityKey k = do 
  ets <- D.selectList [ EntryTagEntryId   D.==. k ] []
  let
    tagKeys = map (entryTagTagId . D.entityVal) ets
  mapM D.getJust tagKeys


getPrevEntry :: Entry -> D.SqlPersistM (Maybe (D.Entity Entry))
getPrevEntry e = D.selectFirst [ EntryPostedAt D.<. entryPostedAt e ] [ D.Desc EntryPostedAt ]

getNextEntry :: Entry -> D.SqlPersistM (Maybe (D.Entity Entry))
getNextEntry e = D.selectFirst [ EntryPostedAt D.>. entryPostedAt e ] [ D.Asc EntryPostedAt ]
