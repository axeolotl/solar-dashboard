DROP VIEW IF EXISTS heizung_pro_tag;
DROP TABLE IF EXISTS heizung;
CREATE TABLE heizung (
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

-- aggregate per local (Europe/Berlin) day, independent of the session time zone
-- of the reading client (Grafana connects with the server default, UTC)
create view heizung_pro_tag as select date_trunc('day', date1, 'Europe/Berlin') as date1, max(heat)-min(heat) as heat_today from heizung group by 1;

SET DateStyle TO 'DMY';
set timezone TO 'Europe/Berlin';

COPY heizung FROM PROGRAM E'find /tmp/SC514 -name \\*.TXT -exec cat \\{\\} \\; | grep -v Date | sed -E \'s/^(([^\t]*\t){25}[^\t]*).*$/\\1/\' | sed \'s/\r//\'';

delete from heizung where s3 > 300;
delete from heizung where s9 > 300;
delete from heizung where s1 > 300;

-- create the read-only user on first run, (re)set its password from config.sh
-- (PG_GRAFANA_PASSWORD, passed in by init-db.sh as psql variable) on every run
SELECT 'CREATE ROLE grafanareader LOGIN' WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'grafanareader')\gexec
ALTER ROLE grafanareader WITH LOGIN PASSWORD :'grafana_password';
GRANT USAGE ON SCHEMA public TO grafanareader;
GRANT SELECT ON public.heizung TO grafanareader;
GRANT SELECT ON public.heizung_pro_tag TO grafanareader;

