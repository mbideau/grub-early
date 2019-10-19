# Makefile for cryptkey-from-usb-mtp
#
# Respect GNU make conventions
#  @see: https://www.gnu.org/software/make/manual/make.html#Makefile-Basics
#
# Copyright (C) 2019 Michael Bideau [France]
#
# This file is part of cryptkey-from-usb-mtp.
#
# cryptkey-from-usb-mtp is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# cryptkey-from-usb-mtp is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with cryptkey-from-usb-mtp.  If not, see <https://www.gnu.org/licenses/>.
#

AUTHOR_NAME         := Michael Bideau
EMAIL_SUPPORT       := mica.devel@gmail.com

# use POSIX standard shell and fail at first error
.POSIX:

# which shell to use
SHELL              := /bin/sh

# binaries
GETTEXT            ?= gettext
XGETTEXT           ?= xgettext
MSGFMT             ?= msgfmt
MSGINIT            ?= msginit
MSGMERGE           ?= msgmerge
MSGCAT             ?= msgcat
GZIP               ?= gzip
TAR                ?= tar
SHELLCHECK         ?= shellcheck

# source
#srcdir            ?= $(shell pwd)
srcdir             ?= .
MAIN_SCRIPT        := $(srcdir)/grub-early.sh
MAIN_SCRIPTNAME    := $(notdir $(MAIN_SCRIPT))
LOCALE_DIR         := $(srcdir)/locale

# temp dir
TMPDIR             ?= $(srcdir)/.tmp

# destination
# @see: https://www.gnu.org/software/make/manual/make.html#Directory-Variables
localedir          ?= $(datarootdir)/locale

# package infos
PACKAGE_NAME       ?= $(basename $(notdir $(MAIN_SCRIPT)))
PACKAGE_VERS       ?= 0.0.1

# locale specific
MAIL_BUGS_TO       := $(EMAIL_SUPPORT)
TEXTDOMAIN         := $(PACKAGE_NAME)
POT_DIR            := $(TMPDIR)/pot
MERGE_POT_FILE     := $(POT_DIR)/$(TEXTDOMAIN).merged.pot
PO_DIR             := $(LOCALE_DIR)
LOCALE_FILES        = $(LANGS:%=$(PO_DIR)/%.po)
MO_DIR             := $(TMPDIR)/locale
POT_MAIN_SCRIPT    := $(addprefix $(POT_DIR)/, $(addsuffix .pot, \
                      $(basename $(notdir $(MAIN_SCRIPT)))))

# charset and languages
CHARSET            := UTF-8
LANGS              := fr
LANGS_PLUS_EN      := en $(LANGS)

# generated files/dirs
LOCALE_DIRS         = $(LANGS:%=$(MO_DIR)/%/LC_MESSAGES)
MO                  = $(addsuffix /$(TEXTDOMAIN).mo,$(LOCALE_DIRS))
POT_SRC_FILES       = $(MAIN_SCRIPT)
POT_DST_FILES       = $(addprefix $(POT_DIR)/, $(addsuffix .pot, \
                      $(basename $(notdir $(POT_SRC_FILES)))))
DIRS                = $(POT_DIR) $(PO_DIR) $(MO_DIR) $(LOCALE_DIRS) $(TMPDIR)

# msginit and msgmerge use the WIDTH to break lines
WIDTH              ?= 100

# binaries flags
GETTEXTFLAGS       ?=
GETTEXTFLAGS_ALL   := -d "$(TEXTDOMAIN)"
XGETTEXTFLAGS      ?=
XGETTEXTFLAGS_ALL  := --keyword --keyword=__tt \
	                   --language=shell --from-code=$(CHARSET) \
	                   --width=$(WIDTH)       \
	                   --sort-output          \
	                   --foreign-user         \
	                   --package-name="$(PACKAGE_NAME)" --package-version="$(PACKAGE_VERS)" \
	                   --msgid-bugs-address="$(MAIL_BUGS_TO)"
MSGFMTFLAGS        ?=
MSGFMTFLAGS_ALL    := --check --check-compatibility
MSGINITFLAGS       ?=
MSGINITFLAGS_ALL   := --no-translator  --width=$(WIDTH)
MSGMERGEFLAGS      ?=
MSGMERGEFLAGS_ALL  := --quiet
MGSCATFLAGS        ?=
MGSCATFLAGS_ALL    := --sort-output --width=$(WIDTH)
GZIPFLAGS          ?=
TARFLAGS           ?= --gzip
SHELLCHECKFLAGS    ?=
SHELLCHECKFLAGS_ALL:= --check-sourced --external-sources --exclude=SC2034,SC1090,SC2174,SC2154,SC2230

# Use theses suffixes in rules
.SUFFIXES: .po .mo .pot .gz .sh .inc.sh .inc.pot

# Do not delete those files even if they are intermediaries to other targets
.PRECIOUS: $(LOCALE_FILES) $(MO_DIR)/%/LC_MESSAGES/$(TEXTDOMAIN).mo

# compiled translations depends on their not-compiled sources
$(MO_DIR)/%/LC_MESSAGES/$(TEXTDOMAIN).mo: $(PO_DIR)/%.po
	 @echo "## Compiling catalogue '$<' to '$@'"
	 @$(MSGFMT) $(MSGFMTFLAGS) $(MSGFMTFLAGS_ALL) --output "$@" "$<"


# translations files depends on the main translation catalogue
%.po: $(MERGE_POT_FILE)
	 @_lang="`basename "$@" '.po'`"; \
	 if [ ! -e "$@" ]; then \
	     _lang_U="`echo "$$_lang"|tr '[[:lower:]]' '[[:upper:]]'`"; \
	     echo "## Initializing catalogue '$@' from '$<' [$${_lang}_$${_lang_U}.$(CHARSET)]"; \
	     $(MSGINIT) $(MSGINITFLAGS) $(MSGINITFLAGS_ALL) --input "$<" --output "$@" \
	                --locale="$${_lang}_$${_lang_U}.$(CHARSET)" >/dev/null; \
	 else \
	     echo "## Updating catalogue '$@' from '$(MERGE_POT_FILE)' [$${_lang}]"; \
	     $(MSGMERGE) $(MSGMERGEFLAGS) $(MSGMERGEFLAGS_ALL) --lang=$$_lang --update "$@" "$<"; \
	     touch "$@"; \
	 fi;


# main translation catalogue depends on individual catalogue files
$(MERGE_POT_FILE): $(POT_DST_FILES)
	 @echo "## merging all pot files into '$@'"
	 @$(MSGCAT) $(MGSCATFLAGS) $(MGSCATFLAGS_ALL) --output "$@" $^


# main tools translation catalogue depends on main tools source file
# and its default configuration
$(POT_MAIN_SCRIPT): $(MAIN_SCRIPT)
	 @echo "## (re-)generating '$@' from '$<' ..."
	 @$(XGETTEXT) $(XGETTEXTFLAGS) $(XGETTEXTFLAGS_ALL) --output "$@" "$<"


# create all required directories
$(DIRS):
	 @echo "## Creating directory '$@'"
	 @mkdir -p "$@"

# to build everything, create directories then 
# all the locale files (they depends on all the rest)
all: $(DIRS) $(MO)

# catch-all
.PHONY: all

# vim:set ts=4 sw=4
