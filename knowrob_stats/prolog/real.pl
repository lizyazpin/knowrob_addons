%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%    Author:        Nicos Angelopoulos, Vitor Santos Costa, Jan Wielemaker
%    E-mail:        Nicos Angelopoulos <nicos@gmx.co.uk>
%    Copyright (C): Nicos Angelopoulos, Universidade do Porto, VU University Amsterdam
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%
%  This file is part of real
%  distributed according to Perl Artistic License
%  check LICENSE file for distribution license
%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

:- module('real', [
     start_r/0,
     end_r/0,
	r/2,
	r/1,
     is_rvar/1,
     is_rvar/2,
     real_citation/2,
     real_debug/0,
     real_nodebug/0,
     real_version/3,
     r_char/2,
     r_wait/0,
     devoff/0,
     devoff_all/0,
     r_serve/0,
     r_thread_loop/0,
     (<-)/1,
	(<-)/2,
	op(950,fx,<-),
	op(950,yfx,<-),
	op(600,xfy,~),
	% op(600,yfx,'..'),
	% op(400,yfx,'%x%'),  % function exists
	% op(400,yfx,'%%'),   % mod 
	% op(400,yfx,'%/%'),  % //
	op(400,yfx,@*@),  % op(400,yfx,'%*%'),  % matrix multiplication: inner product
	op(400,yfx,@^@),  % op(400,yfx,'%o%'),  % outer product ? 
	% op(400,yfx,'%in%'), % function can be called instead
	op(400,yfx,$),
	op(400,yfx,@),
	op(800,fx,@),
     op(400,xfy,=+ ),
	op(100, yf, [])
	% op(100, yf, '()')
     ]).

:- multifile
	user:portray/1.
:- dynamic
	user:portray/1.

:- use_module(library(shlib)).
:- use_module(library(lists)).
:- use_module(library(apply_macros)).
:- use_module(library(charsio)).
:- use_module(library(readutil)).
:- use_module(library(debug)).

:- dynamic( real:r_started/1 ).
:- create_prolog_flag( real, none, [type(atom)] ).

/** <module> An interface to the R statistical software.
---++ Introduction
This library enables the communication with an R process started as a shared library.
It is the result of the efforts of two research groups that have worked in parallel.
The syntactic emphasis on a minimalistic interface.
In the doc/ directory of the distribution there is user's guide, a published paper
and html documentation from PlDoc. There is large number of examples in `examples/for_real.pl`.
By default when the library is loaded an R object is started which will serve the 
R commands. If prefs:start_r_auto(false) is in memory, the R object is not loaded and the user
needs to issue start_r/0 to do that. 
A single predicate (<-/2,<-/1) channels the bulk of the interactions between Prolog and R.  In addition to using R as a shared library, real uses
the c-interfaces of SWI/Yap and R to pass objects in both directions.
The usual mode of operation is to load Prolog values on to R variables and then call
R functions on these values. The return value of the called function can be either placed
on R variable or passed back to Prolog.  It has been tested extensively on current
SWI and YAP on Linux machines but it should also compile and work on MS operating systems and Macs.
Since v1.1 Real supports threads for web services.
In this scenario, the R object is served by the main thread. This is compatible 
with the current Prolog servers ran as Unix services although you need a patched version of 
http_unix_daemon.pl for this type of demployment (one such file is included in Real sources).
See http://stoics.org.uk/~nicos/sware/real/ws.html
and in directory examples/ws_hist
The main modes for utilising the interface are
==
	<- +Rexpr
	<- +Rvar
==
     Print  Rvar or evaluate expression Rexpr in R
==
	+Rvar   <- +PLdata
	+Rexpr  <- +PLdata
	-PLvar  <- +Rvar
	-PLvar  <- +Rexpr
	+Rexpr1 <- +Rexpr2
==
Pass Prolog data to R, pass R data to Prolog or assign an R expression to
an assignable R expression.
---++ Testing
There is a raft of examples packed in a sinlge file that test the library.
==
	?- [pack(real/examples/for_real)].
	?- for_real.
	?- edit( pack(real/examples/for_real) ).
==
---++ Syntax
There are syntactic conventions in R that make unparsable prolog code.
Notably function and variable names are allowed to contain dots, square brackets are used
to access parts of vectors and arrays and functions are allowed empty argument tuples.
We have introduced relevant syntax which allows for easy transition between prolog and R.
Prolog constructs are converted by the library as follows:
     * =|..|= within atoms  ->  =|.|= (ex. =| as..integer(c(1,2,3)) ->  as.integer(c(1,2,3))|= )
     * =|^[]|=  after atoms -> =|[]|= (ex. =|a^[2] -> a[2] |=)
     * =|(.)|= at the end of atoms that are known R functions -> =|()|=  (ex. =|dev..off(.) -> dev.off()|= )
     * =|[]|= -> c() (which equal to R's NULL value)
     * ( f(x) :-  (..))   -> f(x) (...)
     * Lists of lists are converted to matrices. All first level lists must have the same length.
     * Filenames must be given as Prolog strings.
     * R specific operators (eg. %*% should be quoted in Prolog.
     * + prepends strings, both for (Prolog) codes and atoms: +"String" and +'String'
     * If you want to ensure that you do not quote a string, use -"String".
     * Expressions that pose difficulty in translation can always be passed as unquoted Prolog atoms or strings.
	* since  0:1:2  foo()  is valid syntax:  =|<- dev..off() |= works now (with no need for dev..off(.))
	* since  0:1:2  mat[1] is valid syntax:  =|m[1] <- 4|= works now (with no need for m^[...])
---++ Data transfers
R vectors are mapped to prolog lists and matrices are mapped to nested lists.
The convention works the other way around too.
There are two ways to pass prolog data to R. The more efficient one is by using
==
 Rvar <- PLdata
==
Where Pldata is one of the basic data types (number,boolean) a list or a c/n term.
This transfers via C data between R and Prolog. In what follows atomic PLval data
are simply considered as singleton lists.
Flat Pldata lists are translated to R vectors and lists of one level of nesting to R matrices
(which are 2 dimensional arrays in R parlance). The type of values of the vector or matrice is
taken to be the type of the first data element of the Pldata according to the following :
     * integer -> integer
     * float   -> double
     * atom    -> char
     * boolean -> logical
Booleans are represented in prolog as true/false atoms.
Currently arrays of aribtrary dimensions are not supported in the low-level interface.
Note that in R a scalar is just a one element vector.  When passing non-scalars the
interface will assume the type of the object is that of the first scalar until it encounters
something different.
Real will currently re-start and repopulate partial integers for floats as illustrated
below:
==
r <- [1,2,3].         % pass 1,2,3 to an R vector r
R <- r.               % pass contents of R vector r to Prolog variable R
R = [1, 2, 3].
i <- [1,2,3.1].       % r is now a vector of floats, rather than integers
I <- i.
I = [1.0, 2.0, 3.1].
==
However, not all possible "corrections" are currently supported. For instance,
==
?- c <- [a,b,c,1].
ERROR: real:set_r_variable/2: Type error: `boolean' expected, found `a'
==
In the data passing mode we map Prolog atoms to R strings-
==
?- x <- [abc,def].
true.
?- <- x.
[1] "abc" "def"
true.
?- X <- x.
X = [abc, def].
==
In addition, Prolog data can be passed through the expression mechanism.
That is, data appearing in an arbitrary R expression will be parsed and be part of the long
string that will be passed from Prolog to R for evaluation.
This is only advisable for short data structures. For instance,
==
     tut_4a :-
          state <- c(+"tas", +"sa",  +"qld", +"nsw", +"nsw"),
          <- state.
     tut_4b :-
          state <- c(+tas, +sa,  +qld, +nsw, +nsw),
          <- state.
==
Through this interface it is more convenient to be explicit about R chars by Prolog prepending
atoms or codes with + as in the above example.
---++ Examples
==
?- e <- numeric(.).
yes
?- e^[3] <- 17.
yes
?- e[3] <- 17.
yes
?- Z <- e.
Z = ['$NaN','$NaN',17.0]
?- e^[10] <- 12.
yes
?- Z <- e.
Z = ['$NaN','$NaN',17.0,'$NaN','$NaN','$NaN','$NaN','$NaN','$NaN',12.0]
rtest :-
	y <- rnorm(50),               % get 50 random samples from normal distribution
	<- y,                         % print the values via R
	x <- rnorm(y),                % get an equal number of normal samples
     <- x11(width=5,height=3.5),   % create a plotting window
	<- plot(x,y)                  % plot the two samples
     r_wait,                       % wait for user to hit Enter
	% <- dev..off(.).             % old syntax, still supported 
	<- dev..off().                % close the plotting window. foo() now acceptable in supported Prologs
tut6 :-
	d <- outer(0:9, 0:9),
	fr <- table(outer(d, d, "-")),
	<- plot(as..numeric(names(fr)), fr, type="h", xlab="Determinant", ylab="Frequency").
tut4b :-
     state <- [tas,sa,qld,nsw,nsw,nt,wa],
     statef <- factor(state),
     incmeans <- tapply( c(60, 49, 40, 61, 64, 60, 59), statef, mean ),
     <- incmeans.
logical :-
     t <- [1,2,3,4,5,1],
     s <- t==1,
     <- s,
     S <- s,
     write( s(S) ), nl.
==
---++ Info
@author	Nicos Angelopoulos
@author	Vitor Santos Costa
@version	1:1:0, 2013/3/24, thankless_task
@license	Perl Artistic License
@see		http://stoics.org.uk/~nicos/sware/real
@see		pack(real/examples/for_real)
@see		pack(real/doc/real.html)
@see		pack(real/doc/guide.pdf)
@see		pack(real/doc/padl2013-real.pdf)
@see		http://www.r-project.org/
*/

%%%

init_r_env :-
	getenv('R_HOME',Path),
	% done, except if in windows...
	\+ current_prolog_flag(windows, true),
	!,
     debug( real, 'Found R_HOME: ~a', [Path] ).
:- if(current_predicate(win_registry_get_value/3)).
init_r_env :-
	% windows is windows
        current_prolog_flag(windows, true),
	( HKEY='HKEY_LOCAL_MACHINE/Software/R-core/R';
		HKEY='HKEY_CURRENT_USER/Software/R-core/R' ),
        catch(win_registry_get_value(HKEY,'Current Version', Version),_,fail),
	!,
	atomic_list_concat([HKEY,Version],'/',SecondKey),
	win_registry_get_value(SecondKey,'InstallPath', RPath), !,
	setenv('R_HOME',RPath), % this probably does not help (at least not XPs)
	% now we need to have the DLL in our path
     % nicos: although on xp it seems that path has to already be set.
     ( current_prolog_flag(address_bits, 64) ->
          Psf = '\\bin\\x64'
          ;
          Psf = '\\bin\\i386'
     ),
     atomic_list_concat( [RPath,Psf], ToR ),
	install_in_ms_windows(ToR).
:- endif.
init_r_env :-
        current_prolog_flag(unix, true),
	% typical Linux 64 bit setup (fedora)
	current_prolog_flag(address_bits, 64),
	Linux64 = '/usr/lib64/R',
	exists_directory(Linux64), !,
        debug( real, 'Setting R_HOME to: ~a', [Linux64] ),
	setenv('R_HOME',Linux64).
init_r_env :-
        current_prolog_flag(unix, true),
	% typical Linux  setup (Ubuntu)
	Linux32 = '/usr/lib/R',
	exists_directory( Linux32 ), !,
     debug( real, 'Setting R_HOME to: ~a', [Linux32] ),
	setenv('R_HOME',Linux32).
% nicos, fixme: Linux multilib ?
init_r_env :-
	% typical MacOs setup
	exists_directory('/Library/Frameworks'), !,
	install_in_osx.
init_r_env :-
	absolute_file_name( path('R'), This,
			 [ extensions(['',exe]),
			   access(execute),
			   file_errors(fail) % Wouter Beek, 14.03.18
			 ] ),
	dirpath_to_r_home( This, Rhome ),
	exists_directory( Rhome ), !,
        debug( real, 'Setting R_HOME to bin relative: ~a', [Rhome] ),
	setenv('R_HOME',Rhome).
init_r_env :-
     throw( real_error(r_root) ).

% track down binarythrough symbolic links...
dirpath_to_r_home( This0, Rhome ) :-
	read_link(This0, _, This), !,
	dirpath_to_r_home( This, Rhome ).
dirpath_to_r_home( This, Rhome ) :-
     file_directory_name( This, R1 ),
     file_base_name(R1, Execdir) ->
     ( Execdir == bin ->
       Rhome = R1
     ;
       % windows with multiple binaries
       file_directory_name( R1, R2 ),
       file_base_name(R2, bin),
       file_directory_name( R2, Rhome )
     ).

r_home_postfix( 'lib64/R' ) :-
	current_prolog_flag(address_bits, 64).
r_home_postfix( 'lib/R' ).

to_nth( [To|T], To, T ) :- !.
to_nth( [_H|T], To, Right ) :-
	to_nth( T, To, Right ).

% nicos: This should become the standard way.  2013/01/02.
:- if(current_predicate(win_add_dll_directory/1)).
install_in_ms_windows( ToR ) :-
     debug( real, 'Setting up ms-wins dll directory: ~a', [ToR] ),
     win_add_dll_directory( ToR ),
	install_in_ms_windows_path( ToR ).
:- else.
install_in_ms_windows(RPath) :-
     install_in_ms_windows_path( RPath ).
:- endif.

install_in_ms_windows_path(RPath) :-
	getenv('PATH',OPath),
	atomic_list_concat([OPath,';',RPath],Path),
     % if you have problems with R associated dlls, you might also want to add:
	% atomic_list_concat([IPath,';',RPath,'\\modules\\i386'],Path),
     debug( real, 'Changing wins path to: ~a', [Path] ),
	setenv('PATH',Path).

install_in_osx :-
	current_prolog_flag(address_bits, 64),
	Mac64 = '/Library/Frameworks/lib64/R',
	exists_directory(Mac64), !,
     debug( real, 'Setting R_HOME to: ~a', [Mac64] ),
	setenv('R_HOME',Mac64).
install_in_osx :-
	% typical MacOs setup
	MacTypical = '/Library/Frameworks/R.framework/Resources',
	exists_directory(MacTypical), !,
     debug( real, 'Setting R_HOME to: ~a', [MacTypical] ),
	setenv('R_HOME', MacTypical).
install_in_osx :-
	LastMac = '/Library/Frameworks/lib/R',
	( exists_directory(LastMac) ->
		debug( real, 'Setting R_HOME to: ~a', [LastMac] )
		;
		debug( real, 'Setting R_HOME to non-existing: ~a', [LastMac] )
	),
	setenv('R_HOME', LastMac ).

% interface predicates

%%	start_r.
%	Start an R object. This is done automatically upon loading the library,
%    except if prefs:start_r_auto(false) is in memory.
%    Only 1 instance should be started per Prolog session.
%    Multiple sessions will be ignored silently.
%
start_r :-
	current_prolog_flag( real, none ),
	!,
	swipl_wins_warn,
	init_r_env,
	use_foreign_library(foreign(real)),
	init_r,
	set_prolog_flag( real, started ).
start_r.

%%	end_r.
%
%    End the connection to the R object.
%
end_r :-
	stop_r,
	set_prolog_flag( real, none ).

%%	'<-'(+Rvar).
%%	'<-'(+Rexpr).
%
%         If Rvar is an atom and a known R object, then print Rvar on R.
%         Else treat the input as an R expression and pass it on R for interpretation.
%        (Throws result away, if expression is not a <- expression itself).
%
'<-'(X) :-
     r(X).

%%  '<-'(+Rvar, +PLdata ).
%%  '<-'(+Rexpr, +PLdata ).
%%  '<-'(-PLvar, +Rvar ).
%%  '<-'(-PLvar, +Rexpr ).
%%  '<-'(+Rexpr1, +Rexpr2 ).
%
%  Pass Prolog data PLdata to Rvar. PLdata is a term that is one of:
%  an atomic value, flat list or list of depth 2. This mode uses the C-interface to pass
% the value to an R variable.
%
%  Pass PLdata to an assignable R expression.
%
%  Pass Rvar to PLvar variable via the C-interface.
%
%  Evaluate Rexpr and store its return value to PLvar.
%
%  Pass Rexpr1 <- Rexpr2 to R.
%
%  Note that all Rexpr* are first processed as described in the section about syntax before passed to R.
% Real also looks into Rexpressions and passes embeded lists to hidden R variables in order
% to pass large data efficiently.
%
%  c/n terms are recognised as PLdata
% if and only if they contain basic data items in all their arguments that can be
% cast to a single data type. This builds on the c() function of R that is a basic
% data constructor. Currently c/n terms are not recognised within nested expressions.
% But a mechanism similar to the hidden variables for Prolog lists in expressions should
% be easy to implement.
%
'<-'(X,Y) :-
     r(X,Y).

%% r( R )
%
%   Nickname for <-(R).
%
r( R ) :-
	thread_self( Self ),
	Self \== main,
	% current_prolog_flag( real, thread ),
	!,
	r_thread( main, Self, r(R) ).

r( RvarIn ) :-
     (  rvar_identifier(RvarIn,_,RvarCs) ->
        true
        ; (atom(RvarIn),atom_codes(RvarIn,RvarCs))
     ),
	!,
	atom_codes('print( ', PrintOpen), % JW: I think we should be using atoms
	atom_codes(' )', PrintClose),	  % JW: all along
	append([PrintOpen,RvarCs,PrintClose], CmdCodes),
	send_r_codes( CmdCodes ).
r( R ) :-
	rexpr_codes(R,TmpRs,Rcodes,[]),
	!,
	send_r_codes(Rcodes),
	maplist( r_remove, TmpRs ).
r( _Other ) :-
	write( user_error, 'Cannot use input to <-/1.' ), nl, nl,
	fail.

%%	r( ?L, +R ).
%
%    Nickname for <-(L,R).
%
r( A, B ) :-
	thread_self( Self ),
	Self \== main,
	debug( real, 'Calling from thread:~p', Self ),
	!,
	r_thread( main, Self, r(A,B) ).
	% thread_send_message( main, real_call(Caller,Real) ),
	% thread_get_message( Caller, real_ply(Ball,Real) ),
	% fixme: we should be able to write the caught Ball here, except if it is 
	% is thread related, in which case possibilities are probably also limited
	
/*
r( A, B ) :-
	current_prolog_flag( real, thread ),
	!,
     debug( real, 'Using R on thread',  [] ),
	r_thread( r(A,B) ).
	*/
r( Plvar, RvarIn ) :-
     var(Plvar),
     rvar_identifier( RvarIn, RvarIn, _ ),
     !,
     debug( real, 'Assigning to Prolog variable R variable ~a',  [RvarIn] ),
     robj_to_pl_term( RvarIn, Plvar ).
%   Plvar <- Rexpr.
r( Plvar, Rexpr ) :-
     var(Plvar),
     rexpr_codes( Rexpr, TmpRs, Rcodes ),
     !,
     debug( real, 'Assigning to Prolog variable R expression ~s',  [Rcodes] ),
     rexpr_to_pl_term( Rcodes, Plvar ),
     maplist( r_remove, TmpRs ).
%  Rvar <- Plval.
r( RvarIn, PlrExpr ) :-
     assignment( PlrExpr, RvarIn ),
     !.
%  Rexpr1 <- Rexpr2
r( LRexpr, RRexpr ) :-
     rexpr_codes('<-'(LRexpr,RRexpr),TmpRs,Rcodes),
     !,
     send_r_codes( Rcodes ),
     maplist( r_remove, TmpRs ).
r( _Plvar, _Rexpr ) :-
     write( user_error, 'Cannot decipher modality of <-/2. \n ' ), nl,
     fail.

% r_thread_loop.
%
% Starts a loop that serves R calls received from 
% <-/1 and <-/2 calls from other threads.
% It should always be run on thread *main*.
% To stop it, query from any thread in the pool:
% ==
%    <- r_thread_loop_stop.
% ==
% 
r_thread_loop :-
	thread_get_message(main, Mess ),
	r_thread_message( Mess ).

r_thread_message( quit ) :-
	!,
	halt(0).
r_thread_message( real_call(Caller,Goal) ) :-
     debug( real, 'In r_thread_loop got ~p, from ~p', [Goal,Caller] ),
	r_thread_serve( Goal, Caller ).

r_thread_serve( r(r_thread_loop_stop), Caller ) :-
     % debug( real, 'In r_thread_loop2 got ~p from ~p', [Goal,Caller] ),
	% Goal =.. [Name|Args],
     % debug( real, 'Name ~p args ~p', [Name,Args] ),
	% Goal = <-(r_thread_loop_stop),
	!,
     debug( real, 'Caught stop_loop signal from caller: ~p', Caller ).
r_thread_serve( Goal, Caller ) :-
	catch( Goal, All, Ball=All ),
	% catch( with_mutex( real, Goal ), All, Ball=All ),
     debug( real, 'Called ~p, caught ~p', [Goal,Ball] ),
	thread_send_message( Caller, real_ply(Ball,Goal) ),
	r_thread_loop.

%% r_serve.
%
%  Serves any R calls that are waiting on the thread queue.
%  The queue is populated by calls to <-/1 and <-/2 that are called
%  on other threads. The predicate succeeds if there are no calls
%  in the queue.
%
r_serve :-
	thread_peek_message(main, _G),
	!,
	thread_get_message(main, real_call(Caller,Goal) ),
     debug( real, 'In main got ~p, from ~p', [Goal,Caller] ),
	catch( with_mutex( real, Goal ), All, Ball=All ),
     debug( real, 'Called ~p, caught ~p', [Goal,Ball] ),
	thread_send_message( Caller, real_ply(Ball,Goal) ),
	r_serve.
r_serve.

r_thread( Eval, Caller, Real ) :-
	% thread_self(Caller),
	debug( real, 'Sending call ~p from caller ~p to evaluator ~p', [Real,Caller,Eval] ),
	thread_send_message( Eval, real_call(Caller,Real) ),
	thread_get_message( Caller, real_ply(Ball,Real) ),
	debug( real, 'Caller ~p received goal ~p and got exception ~p', [Caller,Real,Ball] ),
	( Ball = Real -> true; throw(real_error(thread(Real,Ball))) ).

%%	is_rvar(+Rvar).
%         True if Rvar is an atom and a known variable in the R environment.
is_rvar( Rvar ) :-
     is_rvar( Rvar, _ ).

%%	is_rvar(+Rvar,-RvarAtom).
%         True if Rvar is a term and a known variable in the R environment.
%         RvarAtom is the atomic representation of the Rvar term.
%
is_rvar( RvarIn, Rvar ) :-
	atom(RvarIn), !,
	is_r_variable(RvarIn),
	RvarIn = Rvar.
is_rvar( RvarIn, Rvar ) :-
     rvar_identifier( RvarIn, Rvar, _RvarAtom ),
     is_r_variable( Rvar ),
     rexpr_codes( mode(Rvar), [], Rmode ),
     rexpr_to_pl_term( Rmode, Plmode ),
     RvarModes  = [character,complex,list,logical,'NULL',numeric,raw,'S4'],
     memberchk( Plmode, RvarModes ).

%%	r_char( +Atomic, +RcharAtom ).
%
%   Wrap an atomic value with double quotes so it can pass as an R char type.
%   This is more or less obsolete. You can use +Atomic directly in R expressions.
%
r_char( Atomic, Rchar ) :-
    atomic( Atomic ),
    !,
    atomic_list_concat( ['"',Atomic,'"'], Rchar ).

%%	devoff.
%  Close the current plot devise without any reporting. Short for <- invisible('dev.off'()').
devoff :-
	<- invisible(-'dev.off()').

%% devoff_all.
%
% Close all open devices.
%
/*
devoff_all :-
     Dev <- dev..cur(.),
     Dev > 1,
     !,
     devoff,
     devoff_all.
	*/
devoff_all.

%% r_wait
%         Currently only waiting for Return to be pressed.
%
r_wait :-
     write('Press Return to continue...'), nl,
     read_line_to_codes(user_input, _).

%% real_debug.
%
%  A common (SWI/Yap) interface for starting debugging messages for real.
%
real_debug :-
     debug(real).

%% real_nodebug.
%
%  A common (SWI/Yap) interface for stopping debugging messages for real.
%
real_nodebug :-
     nodebug(real).

%% real_version( Version,  Date, Note ).
%
%  Version and release Date (data(Y,M,D) term). Note is either a
%  note or nickname for the release. In git development sources this is set to `development´.
%
real_version( 1:1:0, date(2013,3,24), thanksless_task ).
	% 1:0:0, 2013/12/6, sinter_class
	% 0:1:2, 2013/11/3, the_stoic
     % 0:1:0, 2012/12/26, oliebollen

%% real_citation( -Atom, -Bibterm ).
% Succeeds once for each publication related to this library. Atom is the atom representation
% suitable for printing while Bibterm is a bibtex(Type,Key,Pairs) term of the same publication.
% Produces all related publications on backtracking.
real_citation( Atom, bibtex(Type,Key,Pairs) ) :-
    Atom = 'Integrative functional statistics in logic programming \nNicos Angelopoulos, Vítor Santos Costa, Joao Azevedo, Jan Wielemaker, Rui Camacho and Lodewyk Wessels \nProc. of Practical Aspects of Declarative Languages (PADL 2013). Accepted (January, 2013. Rome, Italy).',
    Type = inproceedings,
    Key  = 'AngelopoulosN+2012',
    Pairs = [
               author = 'Nicos Angelopoulos and Vitor Santos Costa and Joao Azevedo and Jan Wielemaker and Rui Camacho and Lodewyk Wessels',
               title  = 'Integrative functional statistics in logic programming',
               booktitle = 'Proc. of Practical Aspects of Declarative Languages}',
               year = 2013,
               month = 'January',
               address = 'Rome, Italy',
               url     = 'http://stoics.org.uk/~nicos/pbs/padl2013-real.pdf'
     ].

%%% end of interface predicates

% maybe add this to the interface ?
r_remove( Plvar ) :-
     <- remove( Plvar ).

start_r_auto :-
	current_predicate( prefs:start_r_auto/1 ),
	prefs:start_r_auto( false ),
	!.
start_r_auto :-
	start_r.

send_r_codes( Rcodes ) :-
     debug( real, 'Sending to R: ~s', [Rcodes] ),
     send_r_command( Rcodes ).

rexpr_codes( Rterm, RTmps, Rcodes ) :-
     rexpr_codes( Rterm, RTmps, Rcodes, [] ).

assignment(PlDataIn, Rvar) :-
     % atom( Rvar ),
     rvar_identifier( Rvar, Rvar, _ ),
     functor( PlDataIn, c, _Arity ),
     send_c_vector(PlDataIn, Rvar), !,
     debug( real, 'Assigned c vector to R variable ~a.', [Rvar] ).

assignment(PlDataIn, Rvar) :-
     % atom( Rvar ),
          % we would like to use rvar_identifier here, instead of atom/1
          % but a$b <- 3 does not work with set_r_variable/2.
     rvar_identifier( Rvar, Rvar, _ ),
     pl_data( PlDataIn, PlData ),
     !,
     % term_to_atom( RvarIn, RvarAtom ),
     set_r_variable(Rvar, PlData),
     debug( real, 'Assigned Prolog data to R variable ~a.', [Rvar] ).

assignment( Rexpr, Rvar ) :-
     rvar_identifier( Rvar, _Rvar, RAssgn ),
     rexpr_codes( '<-'(-RAssgn,Rexpr), TmpRs, Rcodes ),
     !,
     send_r_codes( Rcodes ),
     maplist( r_remove, TmpRs ).

pl_data( PlData, PlData ) :-
     ( number(PlData); PlData=[_|_]; boolean_atom(PlData); PlData = @(_) ).
/*
pl_data( PlDataIn, PlData ) :-
     PlDataIn =.. [c|PlData].
*/

/** rvar_identifier( Rterm, Rvar, Rcodes ).
True if Rterm is an access term for an R variable Rvar and Rcodes
are the codes corresponding to Rterm. Note that it is not the
case that term_to_codes( Rterm, Rcodes ) holds. Rterm might contain code lists
that are contextually interpreted by R as slots or list item labels.
Or, Rterm might contain indices that we translate.
*/

rvar_identifier( Rt, Rv, Rc ) :-
     rvar_identifier_1( Rt, Rv, Ra ),
     !,
     % is_r_variable( Rv ),
     atom_codes( Ra, Rc ).

rvar_identifier_1( Rvar, Rvar, Rvar ) :-
	atom( Rvar ),
     ( catch(term_to_atom(Atom,Rvar),_,fail) ),
     Atom == Rvar.
/*
rvar_identifier_1( A..B, Atom, Atom ) :-
	atom(B),
	rvar_identifier_1( A, Aatom, _ ),
	atomic_list_concat( [Aatom,'.',B], Atom ).
	*/
rvar_identifier_1( A$B, Rv, C ) :-
     rname_atom( B, Batom ),
	rvar_identifier_1( A, Rv, Aatom ),
	% term_to_atom( Aatom$Batom, C ).
     atomic_list_concat( [Aatom,'$',Batom], C ).
rvar_identifier_1( A@B, Rv, C ) :-
     rname_atom( B, Batom ),
	rvar_identifier_1( A, Rv, Aatom ),
     atomic_list_concat( [Aatom,'@',Batom], C ).
rvar_identifier_1( []([[B]],A), Rv, C ) :-
     rvar_identifier_1( A, Rv, Aatom ),
     rexpr_codes(B, [], BCs, [] ),
     atom_codes( Batom, BCs ),
     atomic_list_concat( [Aatom,'[[',Batom,']]'], C ).
rvar_identifier_1( A^[[B]], Rv, C ) :-
     rvar_identifier_1( A, Rv, Aatom ),
     rexpr_codes(B, [], BCs, [] ),
     atom_codes( Batom, BCs ),
     atomic_list_concat( [Aatom,'[[',Batom,']]'], C ).
rvar_identifier_1( [](B,A), A, C ) :-
     indices_to_string( B, BCs, [] ),
     atom_codes( Batom, BCs ),
	atom_concat( A, Batom, C ).
rvar_identifier_1( A^B, A, C ) :-
     atom( A ),
     is_list( B ),
     indices_to_string( B, BCs, [] ),
     atom_codes( Batom, BCs ),
	atom_concat( A, Batom, C ).

/** rexpr_codes(V,_,_).
     Generate (or parse) an R expression as codes from/to a Prolog term.
*/
rexpr_codes(V,[]) -->
	{ var(V) }, !,
	{ throw(error(instantiation_error,r_interface)) }.
rexpr_codes(T,[]) -->
	{ current_predicate(string/1), string(T), 
	  !,
	  format( codes(S), "~s", [T]) 
	},
	"\"", S, "\"".
rexpr_codes(+A,[]) -->
	!,
	{ atom(A) -> format(codes(S), '~a', [A]) ; format(codes(S), "~s", [A]) },
	"\"", S, "\"".
rexpr_codes(-A,[]) -->
	!,
	{ atom(A) -> format(codes(S), '~a', [A]) ; format(codes(S), "~s", [A]) },
	S.
rexpr_codes(=+(A,B),List) -->
	!,
	rexpr_codes((A = +B),List).
rexpr_codes(Array,TmpRs) -->
	{ Array = [_|_] },
	array_to_c(Array,TmpV), !,
	{ TmpRs = [TmpV] }.
rexpr_codes(A,[]) -->
	{ compound(A,'()',[Fname]) },
	!,
	add_atom(-Fname), "()".
rexpr_codes(A,[]) -->        					% fixme: remove when .
	{ compound(A,Name,[_]), arg(1,A,'.') }, !,
	add_atom(-Name), "()".
/*   This can be used if we want c() to be passed by lists,
but it currently does not accommodate c(1:3,1:3)
rexpr_codes(A,List) -->
	{
         A =.. [c|B], B \== []
        },
	!,
	rexpr_codes(B,List).
        */
/* atom is already protected */
/*
rexpr_codes(A,[]) -->
	{ atom(A), is_rvar(A, _) }, !,
        add_atom(-A).
        */
rexpr_codes(A,[]) -->
	/* string */
	{ atom(A) }, !,
	add_atom(-A).
rexpr_codes(A,[]) -->
	{ number(A) }, !,
	add_number(A).
rexpr_codes(AKey, TmpRs) -->
	{ compound(AKey,[], [[[Key]], A]) },
     !,
	% rexpr_unquoted(A, [] ),
	rexpr_codes(A, Atmp ),
     "[[", rexpr_codes(Key, Ktmp), "]]",
     { append(Atmp,Ktmp,TmpRs) }.
rexpr_codes(A^[[Key]], TmpRs) -->
     !,
	% rexpr_unquoted(A, [] ),
	rexpr_codes(A, Atmp ),
     "[[", rexpr_codes(Key, Ktmp), "]]",
     { append(Atmp,Ktmp,TmpRs) }.
rexpr_codes(AList, TmpRs) -->
	{ compound(AList, [], [List,A]) },
	!,
	rexpr_codes(A, TmpRs),
	indices_to_string( List ).
rexpr_codes(A^List, TmpRs) -->
	{ is_list(List) }, !,
	rexpr_codes(A, TmpRs),
	% rexpr_unquoted(A, TmpRs),
	indices_to_string( List ).
rexpr_codes(A$B,TmpA) -->
	!,
	rexpr_codes( A, TmpA ),
	% rexpr_unquoted( A, TmpA ),
	"$",
	add_name( B ).
rexpr_codes(A@B,TmpA) -->
	!,
	rexpr_codes( A, TmpA ),
	% rexpr_unquoted( A, TmpA ),
	"@",
	add_name( B ).
/*
rexpr_codes(A1..A2,TmpRs) --> !,
	% rexpr_unquoted(A1, TmpRs1),
	rexpr_codes(A1, TmpRs1),
	".",
	% rexpr_unquoted(A2, TmpRs2),
	rexpr_codes(A2, TmpRs2),
     { append(TmpRs1, TmpRs2, TmpRs) }.
	*/
% R function definition
rexpr_codes((A1 :- A2), TmpRs) -->
	!,
	rexpr_codes(A1,TmpA1),
	" ",
	rexpr_codes(A2,TmpA2),
	{append(TmpA1,TmpA2,TmpRs)}.

rexpr_codes(S,TmpRs) -->
	{ 
	  arity(S, NaIn, 2),
	  binary(NaIn,Na), atom_codes(Na,NaS),
          arg(1,S,A1), arg(2,S,A2)
        }, !,
	   % fixme: we need something better in the following line (nicos)
        left(Na),
	rexpr_codes(A1,TmpA1),
	" ", NaS, " ",
	rexpr_codes(A2,TmpA2),
	right(Na),
        {append(TmpA1,TmpA2,TmpRs)}.
rexpr_codes(S,TmpRs) -->
	{ compound( S, F, Args ) },
	% { S =.. [F|Args], F \== '.' },
	add_atom( -F ),
	"(",
	rexprs_codes(Args, true, F, TmpRs),
	")".

left(Na)  --> ({no_brace(Na)} -> "" ; "(").
right(Na) --> ({no_brace(Na)} -> "" ; ")").

no_brace(<-).
no_brace(=).
no_brace(+).

rexprs_codes([], _, _, []) --> [].
rexprs_codes([Arg|Args], Fin, Func, TmpRs) -->
	( { Fin == true } -> "" ; " ," ),
	rexpr_codes(Arg, TmpA),
	% { N1 is N+1 },
	rexprs_codes(Args, false, Func, TmpAs),
	{append(TmpA, TmpAs, TmpRs)}.

/* trying to remove this...
rexpr_unquoted(A, TmpRs) -->
	( { atom(A) } ->
	    add_atom(-A), { TmpRs = [] }
	;
	  rexpr_codes(A , TmpRs)
        ).
        */

/* obsolete ?
literal(1, library).
literal(1, require).
*/

indices_to_string( List ) -->
	"[",
	index_to_string( List ),
	"]".

index_to_string( [] ) --> [].
index_to_string( [H|T] ) -->
     index_element_to_string( H ),
     index_comma( T ),
     index_to_string( T ).

index_element_to_string( * ) -->
	[].
index_element_to_string( List ) -->
	{ is_list(List) },
	!,
	"c(", index_to_string( List ), ")".
index_element_to_string( +Atom ) -->
	{ atom(Atom), !, atom_codes(Atom, Codes) },
	"'", Codes, "'".
index_element_to_string( -El ) -->
	"-",
	index_element_to_string(El).
index_element_to_string( ElR:ElL ) -->
	index_element_to_string(ElR),
	":",
	index_element_to_string(ElL).
index_element_to_string( +String ) -->  % fixme: remove at .
	{ is_list(String) }, !,
	"\"", String, "\"".
index_element_to_string( +String ) -->
	{ string(String) }, !,
	"\"", String, "\"".
index_element_to_string( CExp ) -->
	{ CExp =.. [c|Cs] }, !,
	"c(", index_to_string(Cs), ")".
index_element_to_string( Oth ) -->
	{ (integer(Oth);atom(Oth);compound(Oth)), !, write_to_chars(Oth,Codes) },
	Codes.
index_element_to_string( CExp ) -->
	{ throw(cannot_process_index(CExp)) }.

index_comma( [] ) --> !, [].
index_comma( _ ) -->
     !,
     ",".

/* obsolete ?
%% codes_string(Codes,Quoted).
% check a list is full of (utf ?) codes
% while replacing any " with \" to produce Quoted from Ascii
%
codes_string([],[]).
codes_string(.(C,Cs),Q) :-
	integer(C),
	% <=nicos.  char_type(C,ascii),
        % <=nicos.   \+ char_type(C,cntrl),
	char_my_utf8(C),
	sew_code( C, Q, T ),
	codes_string(Cs,T).
char_my_utf8( C ) :-
	char_type(C,graph),
	!.
char_my_utf8( C ) :-
	char_type(C,white).
%% ascii_code_sew( C, Q, T ).
%  Sew C or its quoted form on list Q with its tail returned in T.
%
sew_code( 34, [0'\\,0'"|T], T ) :- !.
sew_code( C, [C|T], T ).
*/

%% add_name( Name ).
%
% first cut in supporting places where R is expecting "names or string constants"
% as in the RHS of $ and @
%
add_name( Name ) -->
     { ( atomic(Name)  -> Fo = '~a'; Fo = '~s' ),
	  format(codes(Out), Fo, [Name])
     },
	Out.

%% rname_atom( Rname, Atom ).
%
%  Holds for atomic Atom a map of Rname.
%  If Rname is a list is assumed to be a list of codes that is
%  atom_code(/2)d to Atom.
%
rname_atom( Rname, Atom ) :-
     ( atomic(Rname) ->
          Atom = Rname
          ;
          atom_codes( Rname, Atom )
     ).

%
% a nil atom in Prolog is likely to be the empty string in R.
%
add_atom([]) --> !,
	"\"\"".
add_atom( -A ) -->
	!,
	{ format(codes(Out), '~a', [A]) },
	Out.
add_atom([C|Codes] ) -->
	!,
	{ format(codes(Out), '"~s"', [C|Codes]) },
	Out.
% handle atoms that are explicitly quoted (r_char)
add_atom(A) -->
	{ atom_codes(A, Codes) },
	check_quoted(A, Codes).

check_quoted(true, _) --> !, "TRUE".
check_quoted(false, _) --> !, "FALSE".
check_quoted(A, _) --> { is_r_variable(A) }, !,
	{ format(codes(Codes), '~a', [A]) },
	Codes.
check_quoted(A, _) -->
	{ format(codes(Codes), '"~a"', [A]) },
	Codes.


/* no longer used ?
add_string_as_atom( [] ) --> [] .
add_string_as_atom( [H|Tail] ) -->
	( { H =:= "\"" } ->
            ( { Tail == [] } -> "\"" ; "\\\"" )
        ;
        [H]
        ),
	add_string_as_atom( Tail ).
     */


add_number(El) -->
	{ number_codes(El, Codes) },
	Codes.

array_to_c(Array,Rv) -->
	{
          fresh_r_variable(Rv),
          set_r_variable(Rv,Array),
          atom_codes(Rv,RvCodes)
        },
	RvCodes.

fresh_r_variable(Plv) :-
     between( 1, 10000, I ),
     atomic_list_concat([pl,v,I], '_', Plv),
     \+ is_rvar(Plv),
     !.

% hmmmm
% originally this (binary/1) included a call to exist,
% this rightly fails on lm(speeds~exprs)
% we are converting this to an operators version and we might
% need to introduce a top-level version that checks for functions
binary( Plname, Rname ) :-
     current_op( _, Assoc, real:Plname ),
	binary_real_r( Plname, Rname ), 
     once( binary_op_associativity( Assoc ) ).
     % atomic_list_concat( [exists,'("',Rname,'",mode="function")'],  Atom ),
     % atom_codes( Atom, Rcodes ),
     % rexpr_to_pl_term( Rcodes, Rbool ),
     % Rbool == true.

binary_real_r( Plname, Rname ) :-
	binary_real_op( Plname, Rname ),
	!.
binary_real_r( OpName, OpName ).

%% binary_real_op( +Plname, -Rname ).
%
% Rname is R's operator name for Plname. We only to define cases where Plname \== Rname.
%
binary_real_op(  @*@, '%*%' ).
binary_real_op(  @^@, '%o%' ).
binary_real_op(  //, '%/%' ).
binary_real_op( mod, '%%'  ).

binary_op_associativity( yfx ).
binary_op_associativity( xfy ).
binary_op_associativity( xfx ).

boolean_atom( true ).
boolean_atom( false ).

% Only on SWI, bug Vitor for at_halt/1.
halt_r :-
	r_started(_),
	retractall( r_started(_) ),
	devoff_all,
	end_r,
	!.
halt_r.

% makes some sense of SWI v7's half-house extensions on compounds:
%
compound( Term, Name, Args ) :-
	current_predicate( compound_name_arguments/3 ),
	!,
	compound( Term ),
	compound_name_arguments( Term, Name, Args ).
compound( Term, Name, Args ) :-
	Term =.. [Name|Args].

arity( Term, Name, Arity ) :-
	current_predicate( compound_name_arity/3 ),
	!,
	compound( Term ),
	compound_name_arity( Term, Name, Arity ).
arity( Term, Name, Arity ) :-
	functor( Term, Name, Arity ).

swipl_wins_warn :-
	current_prolog_flag(hwnd,_), % true iff ran via swipl-win.exe
	!,
	L = "    library(real) notice: ",
	A = "         There is a known issue with swipl-win.exe.",
	B = "         R's I/O streams cannot be connected to those of Prolog.",
	C = "         So for instance, <- print(x) does not print x to the terminal.",
	D = "         All other functionalities are fine.",
	E = "         To circumvent use things like X <- x, write( x ).",
	F = "         If you need printing on console from R, you can start SWI via swipl.exe",
	Lines = [nl,nl,L,nl,nl,A,nl,B,nl,C,nl,D,nl,E,nl,F,nl,nl],
	print_message_lines(current_output, '', Lines ).
swipl_wins_warn.

% error handling
:- multifile prolog:message//1.

prolog:message(unhandled_exception(real_error(Message))) -->
	{ debug( real, 'Unhandled ~p', Message ) },
	message(Message).

prolog:message(real_error(Message)) -->
	{ debug( real, 'Real error ~p', Message ) },
	message(Message).
	
message( correspondence ) -->
     ['R was unable to digest your statement, either syntax or existance error.' - [] ].
message( r_root ) -->
     ['Real was unable to find the R root directory. \n If you have installed R from sources set $R_HOME to point to $PREFIX/lib/R.\n You should also make sure libR.so is in a directory appearing in $LD_LIBRARY_PATH' - [] ].
message( thread(G,real_error(Exc)) ) -->
	% ( Ball = Real -> true; throw(real_error(thread(Real,Ball))) ).
	{ debug( real, 'Exception ~p', Exc ) },
	message( Exc ),
	['\nR above was caught from thread execution while invoking ~p' - [G] ]. 
% error(existence_error(r_variable,x),context(real:robj_to_pl_term/2,_G395)
% message( thread(G,error(existence_error(r_variable,X),_,_)) ) -->
message( thread(G,error(Error,Context)) ) -->
	% ( Ball = Real -> true; throw(real_error(thread(Real,Ball))) ).
	{ debug( real, 'Attempt to print error/2 ball ~p', error(Error,Context) ) },
	{ print_message( error, error(Error,Context)  ) },
	['Above error was caught from thread execution while invoking ~p' - [G] ]. 
message( thread(G,Exc) ) -->
	{ debug(real,'In with ~p',Exc) },
     ['R thread was unable to digest your statement ~p, and caught exception: ~p.' - [G,Exc] ].

user:portray( r(R) ) :-
	format('<- ~w', [R] ).
user:portray( r(L,R) ) :-
	format('~w <- ~w', [L,R]).
	% write( L <- R ).

:- ( current_prolog_flag(version_data,swi(_,_,_,_)) -> at_halt(halt_r); true ).
:- initialization(start_r_auto, now).
