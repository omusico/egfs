# leave these lines alone
.SUFFIXES: .erl .beam .yrl

.erl.beam:
	erlc -W $<

HOSTNAME = $(shell hostname)

ERL = erl -boot start_sasl -config system -setcookie carrier 

all: compile

compile: ${MODS:%=%.beam} 
	erl -make	

## run an application from the makefile

fs:compile
	${ERL} -pa ../lib -sname  ${HOSTNAME}fusefs -s ping_server ping -s crypto start 
	
# remove all the code

clean:	
	rm -rf *.beam erl_crash.dump

