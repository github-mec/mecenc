CC      = g++
CCARG   = -O2 -std=c++0x
OBJ     = ts_cleaner.o
PROGRAM = ts_cleaner

$(PROGRAM): $(OBJ)
	$(CC) $(CCARG) -o $@ $(OBJ) $(SYSLIB)
	rm $(OBJ)

.cc.o:
	$(CC) $(CCARG) -c $<

clean:
	rm $(PROGRAM)
