DROP TABLE heizung_upd;
CREATE TABLE heizung_upd (
date1  timestamp (0) with time zone primary key,
S1   real, 
S2   real,
S3   real,
S4   real,
S5   real,
S6   real,
S7   real,
S8   real,
S9   real,
S10  real,
V40  real,
CS10 real,
FlowRotor        real,      
RPS_Temperature  real,
RPS_Pressure     real,
R1      real,
R2      real,
R3      real,
R4      real,
R5      real,
Date2    timestamp (0) with time zone,
Heat    	integer,
Heat_today  integer,   
Heat_week   integer,
Power		integer
);

SET DateStyle TO 'DMY';
set timezone TO 'Europe/Berlin';

COPY heizung_upd FROM PROGRAM E'cat /tmp/SC514/delta.txt | grep -v Date | sed -E \'s/^(([^\t]*\t){25}[^\t]*).*$/\\1/\' | sed \'s/\r//\'';

delete from heizung_upd where s3 > 300;
delete from heizung_upd where s9 > 300;
delete from heizung_upd where s1 > 300;

delete from heizung where date1 IN (select date1 FROM heizung_upd);
insert into heizung select * from heizung_upd;
