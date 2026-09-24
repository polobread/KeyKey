SQLITE3 = sqlite3

INSERTER = ./insert-file-into-db.rb
PREPOPULATE_TABLE_NAME = prepopulated_service_data
ONEKEY_SERVICE_KEY = onekey_services
ONEKEY_DATA_SOURCE = ../OnlineData/OneKey.plist
CMSG_SERVICE_KEY = canned_messages
CMSG_DATA_SOURCE = ../OnlineData/CannedMessages.plist

DB = ../CookedDatabase/KeyKey.db

TMPDIR = ./Intermediates

CONVERT_TOOL = ../../../Frameworks/Formosa/Tools/convert-bpmf-cin.rb
NATIVE_BOPOMOFO_DIR = ../../../Frameworks/Formosa/Ruby/native_bopomofo
NATIVE_BOPOMOFO_BUNDLE = $(NATIVE_BOPOMOFO_DIR)/native_bopomofo.bundle
NATIVE_BOPOMOFO_CPP = $(NATIVE_BOPOMOFO_DIR)/native_bopomofo.cpp
NATIVE_BOPOMOFO_EXTCONF = $(NATIVE_BOPOMOFO_DIR)/extconf.rb
NATIVE_BOPOMOFO_MAKEFILE = $(NATIVE_BOPOMOFO_DIR)/Makefile

ASSOC_COOKER = ./AssociatedPhraseCooker.rb
OCC_TO_LM = ./phrase-occ-to-lm.rb
SMART_COOKER = ./SmartMandarinCooker.rb

# One collection per file. Stable source identifiers come from the path;
# product display-name overrides come from COLLECTION_DISPLAY_NAMES.
COLLECTION_DIR = ../../../../DataSource
COLLECTION_DISPLAY_NAMES = $(COLLECTION_DIR)/AssociatedPhraseCollectionNames.tsv
COLLECTIONS = $(COLLECTION_DIR)/McBopomofo/phrase.occ \
	$(wildcard $(COLLECTION_DIR)/chichi77Collection/phrase.*.tsv)
PEOPLE_COLLECTIONS = $(wildcard $(COLLECTION_DIR)/chichi77Collection/phrase.people-*.tsv)
SMART_OCC = $(COLLECTION_DIR)/McBopomofo/phrase.occ
SMART_MAPPINGS = $(COLLECTION_DIR)/McBopomofo/BPMFMappings.txt
SMART_SUPPLEMENTAL_LEXICON = $(COLLECTION_DIR)/AISyntheticBigram/supplemental-lexicon.tsv
SMART_NUMERIC_LEXICON = $(COLLECTION_DIR)/AISyntheticBigram/numeric-unit-lexicon.tsv
SMART_ARTICLE_CORPUS = $(COLLECTION_DIR)/AISyntheticBigram/article-corpus-2300-exact-dedup.txt
SMART_BIGRAM_CORPORA = $(COLLECTION_DIR)/AISyntheticBigram/corpus-v1.txt \
	$(COLLECTION_DIR)/AISyntheticBigram/corpus-v2.txt \
	$(COLLECTION_DIR)/AISyntheticBigram/corpus-v3.txt \
	$(COLLECTION_DIR)/AISyntheticBigram/corpus-typing-feedback.txt \
	$(SMART_ARTICLE_CORPUS)
SMART_SQL = $(TMPDIR)/SmartMandarin.sql

SOURCEDIR = ../../../DataTables
SRC = $(TMPDIR)/bpmf-ext-absorder.cin \
	$(SOURCEDIR)/bpmf-punctuations.cin \
	$(SOURCEDIR)/cj-ext.cin \
	$(SOURCEDIR)/simplex-ext.cin \
	$(SOURCEDIR)/cj-punctuations-halfwidth.cin \
	$(SOURCEDIR)/cj-punctuations-mixedwidth.cin \
	$(SOURCEDIR)/bopomofo-correction.cin
	
TOOL = ../../../Frameworks/OpenVanilla/Tools/cin-to-sqlite.rb

# creates the db file
all: createdir $(DB)

createdir:
	mkdir -p $(TMPDIR)

$(DB): $(SRC) $(COLLECTIONS) $(COLLECTION_DISPLAY_NAMES) $(OCC_TO_LM) $(ASSOC_COOKER) collection-name.rb verify-smart-mandarin-db.py $(SMART_SQL)
	rm -f $(DB)
	cat Schema.sql | $(SQLITE3) $(DB)
	$(SQLITE3) $(DB) < $(SMART_SQL)
	$(TOOL) $(TMPDIR)/bpmf-ext-absorder.cin Mandarin-bpmf-cin | $(SQLITE3) $(DB)
	$(TOOL) $(SOURCEDIR)/bpmf-punctuations.cin Mandarin-bpmf-cin --chardef-only | $(SQLITE3) $(DB)
	$(TOOL) $(SOURCEDIR)/cj-ext.cin Generic-cj-cin | $(SQLITE3) $(DB)
	$(TOOL) $(SOURCEDIR)/simplex-ext.cin Generic-simplex-cin | $(SQLITE3) $(DB)
	$(TOOL) $(SOURCEDIR)/cj-punctuations-halfwidth.cin Punctuations-cj-halfwidth-cin | $(SQLITE3) $(DB)
	$(TOOL) $(SOURCEDIR)/cj-punctuations-mixedwidth.cin Punctuations-cj-mixedwidth-cin | $(SQLITE3) $(DB)
	$(TOOL) $(SOURCEDIR)/bopomofo-correction.cin BopomofoCorrection-bopomofo-correction-cin | $(SQLITE3) $(DB)
	$(INSERTER) $(DB) $(PREPOPULATE_TABLE_NAME) $(ONEKEY_SERVICE_KEY) $(ONEKEY_DATA_SOURCE)
	$(INSERTER) $(DB) $(PREPOPULATE_TABLE_NAME) $(CMSG_SERVICE_KEY) $(CMSG_DATA_SOURCE)	
	@if [ -n "$(PEOPLE_COLLECTIONS)" ]; then \
		awk -F'\t' 'FNR > 1 { print $$1 }' $(PEOPLE_COLLECTIONS) | sort -u > $(TMPDIR)/exclusions.txt; \
	else \
		: > $(TMPDIR)/exclusions.txt; \
	fi
	@for f in $(COLLECTIONS); do \
		name=`basename $$f | sed -e 's/^phrase\.//' -e 's/\.occ$$//' -e 's/\.tsv$$//'`; \
		case $$f in */McBopomofo/*) name=McBopomofo;; esac; \
		case $$f in \
			*/McBopomofo/*) exclude=$(TMPDIR)/exclusions.txt;; \
			*) exclude=;; \
		esac; \
		ruby -E UTF-8 $(OCC_TO_LM) $$f $$exclude > $(TMPDIR)/assoc-$$name.lm && \
		ruby -E UTF-8 $(ASSOC_COOKER) $(TMPDIR)/assoc-$$name.lm $(TMPDIR)/assoc-$$name.sql $$name && \
		$(SQLITE3) $(DB) < $(TMPDIR)/assoc-$$name.sql && \
		ruby -E UTF-8 ./collection-name.rb $$f $$name $(COLLECTION_DISPLAY_NAMES) | $(SQLITE3) $(DB) || exit 1; \
	done
	python3 ./verify-smart-mandarin-db.py $(DB)

$(SMART_SQL): createdir $(SMART_COOKER) $(SMART_OCC) $(SMART_MAPPINGS) $(SMART_SUPPLEMENTAL_LEXICON) $(SMART_NUMERIC_LEXICON) $(SMART_BIGRAM_CORPORA) $(TMPDIR)/bpmf-ext-absorder.cin
	ruby -E UTF-8 $(SMART_COOKER) $(SMART_OCC) $(SMART_MAPPINGS) $(TMPDIR)/bpmf-ext-absorder.cin --lexicon $(SMART_SUPPLEMENTAL_LEXICON) --lexicon $(SMART_NUMERIC_LEXICON) $(SMART_BIGRAM_CORPORA) > $@

$(SMART_ARTICLE_CORPUS): $(COLLECTION_DIR)/AISyntheticBigram/build-versioned-article-corpus.py \
	$(COLLECTION_DIR)/AISyntheticArticles/typing-articles-v2.jsonl \
	$(COLLECTION_DIR)/AISyntheticArticles/typing-articles-v3.jsonl \
	$(COLLECTION_DIR)/AISyntheticArticles/typing-articles-v4.jsonl
	python3 $(COLLECTION_DIR)/AISyntheticBigram/build-versioned-article-corpus.py

$(TMPDIR)/bpmf-ext-absorder.cin: createdir $(SOURCEDIR)/bpmf-ext.cin $(CONVERT_TOOL) $(NATIVE_BOPOMOFO_BUNDLE)
	ruby -I $(NATIVE_BOPOMOFO_DIR) $(CONVERT_TOOL) < $(SOURCEDIR)/bpmf-ext.cin > $(TMPDIR)/bpmf-ext-absorder.cin
	
$(NATIVE_BOPOMOFO_BUNDLE): $(NATIVE_BOPOMOFO_MAKEFILE) $(NATIVE_BOPOMOFO_CPP)
	make -C $(NATIVE_BOPOMOFO_DIR)
	
$(NATIVE_BOPOMOFO_MAKEFILE): $(NATIVE_BOPOMOFO_EXTCONF)
	ruby -C $(NATIVE_BOPOMOFO_DIR) extconf.rb

clean:
	rm $(DB)
	rm -rf $(TMPDIR)
