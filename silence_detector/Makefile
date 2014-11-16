CC      = g++
CCARG   = -O2
OBJ     = silence_detector.o
PROGRAM = silence_detector

$(PROGRAM):  $(OBJ)
	$(CC) $(CCARG) -o $@ $(OBJ) $(SYSLIB)
	rm $(OBJ)

.cc.o:
	$(CC) $(CCARG) -c $<

check-syntax:
	$(CC) -fsyntax-only $(CHK_SOURCES)

clean:
	rm $(PROGRAM)
