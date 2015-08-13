CC      = g++
CCARGS  = -g --std=c++11
OBJ     = sponsor_detector.o
PROGRAM = sponsor_detector

$(PROGRAM):  $(OBJ)
	$(CC) -o $@ $(OBJ) $(SYSLIB) `pkg-config opencv --libs`
	rm $(OBJ)

.cc.o:
	$(CC) $(CCARGS) -c $< `pkg-config opencv --cflags`

check-syntax:
	$(CC) -fsyntax-only $(CHK_SOURCES)

clean:
	rm $(PROGRAM)
