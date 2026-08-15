# McBopomofo data

Vendored from https://github.com/openvanilla/McBopomofo under the MIT licence,
which is reproduced here in full as `LICENSE.txt`.

    Copyright (c) 2011-2026 Mengjuei Hsieh et al.

Taken at commit `73d0379eca621377fb46416ceb4a7dc9bb576d47`, 2026-08-09. The
files are byte-for-byte copies of `Source/Data/` in that revision.

## Files

`phrase.occ` -- 161,429 lines of `word count`. 136,300 of them are two to four
Han characters, and 98,014 of those have a count of at least one.

`BPMFMappings.txt` -- 145,225 lines of `word reading`, where the reading is
space-separated bopomofo syllables. 133,701 are multi-character words.

## Why these two

`DataSource/` shipped empty in 2012 because the language model was cooked from
the Sinica corpus, which Yahoo could not redistribute. Everything that model
provided went with it: phrase input, and the associated phrases that follow a
committed character.

`phrase.occ` supplies what the associated phrase table needs -- words and how
often they occur -- under a licence that permits redistribution.
`BPMFMappings.txt` supplies readings, which associated phrases do not use but a
phrase input model would.

## What still is not here

Phrase input needs more than a word list. It needs the unigram and bigram model
`Makefile.SmartMandarin` builds, and that makefile depends on
`PrecompiledTools/PhraseTool` and `cerod_build`, neither of which was part of
the open-source release. These files do not close that gap.
