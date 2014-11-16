MAKE        = make
MAKE_DIRS   = silence_detector ts_cleaner

.PHONY: all $(MAKE_DIRS)

all: $(MAKE_DIRS)

$(MAKE_DIRS):
	${MAKE} -C $@
