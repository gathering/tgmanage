create table switchtypes (
	switchtype varchar not null primary key,
	ports varchar not null
);

create table switches (
	switch serial not null primary key,
	ip inet not null,
	sysname varchar not null,
	switchtype varchar not null references switchtypes,
	last_updated timestamp,
	locked boolean not null default 'f'
);

create table poll (
	time timestamp not null,
	switch integer not null references switches,
	port integer not null,
	bytes_in bigint not null,
	bytes_out bigint not null,

	primary key ( time, switch, port )
);
create index poll_switch_port on poll ( switch, port );
