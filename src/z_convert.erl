%% @author Rusty Klophaus
%% @copyright Copyright (c) 2008-2009 Rusty Klophaus, Copyright (c) 2009-2021 Marc Worrell
%%
%% @doc Conversion functions for all kinds of data types. Changes to
%% Rusty's version: added date conversion, undefined handling and more
%% to_bool cases.

%% Copyright 2009-2021 Marc Worrell
%%
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%%
%%     http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License.

-module(z_convert).
-author("Rusty Klophaus").
-author("Marc Worrell <marc@worrell.nl>").
-author("Arjan Scherpenisse <arjan@scherpenisse.net>").

-define(ST_JUTTEMIS, {{9999,8,17}, {12,0,0}}).

-export ([
          clean_lower/1,
          to_list/1,
          to_flatlist/1,
          to_atom/1,
          to_binary/1,
          to_binary/2,
          to_integer/1,
          to_float/1,
          to_bool_strict/1,
          to_bool/1,
          to_utc/1,
          to_localtime/1,
          to_datetime/1,
          to_date/1,
          to_time/1,
          to_isotime/1,
          to_json/1,
          unicode_to_utf8/1,

          convert_json/1,
          ip_to_list/1,
          ip_to_long/1,
          long_to_ip/1
]).


%%% CONVERSION %%%


%% @doc Convert to lower case, strip surrounding whitespace.
-spec clean_lower(binary()|list()|atom()) -> binary().
clean_lower(L) -> z_string:trim(z_string:to_lower(L)).


%% @doc Convert (almost) any value to a list.
-spec to_list(term()) -> string().
to_list(undefined) -> "";
to_list(<<>>) -> "";
to_list({rsc_list, L}) -> L;
to_list(L) when is_list(L) -> L;
to_list(A) when is_atom(A) -> atom_to_list(A);
to_list(B) when is_binary(B) -> binary_to_list(B);
to_list(I) when is_integer(I) -> integer_to_list(I);
to_list(F) when is_float(F) -> z_mochinum:digits(F).


%% @doc Flatten list and convert to string.
-spec to_flatlist(term()) -> string().
to_flatlist(L) when is_list(L) ->
	case z_string:is_string(L) of
		true -> L;
		false -> lists:flatten(to_list(iolist_to_binary(L)))
	end;
to_flatlist(L) ->
	lists:flatten(to_list(L)).


%% @doc Convert (almost) any value to an atom.
-spec to_atom(term()) -> atom() | undefined.
to_atom(<<>>) -> undefined;
to_atom("") -> undefined;
to_atom(A) when is_atom(A) -> A;
to_atom(B) when is_binary(B) -> binary_to_atom(B, utf8);
to_atom(I) when is_integer(I) -> list_to_atom(integer_to_list(I));
to_atom(L) when is_list(L) -> list_to_atom(binary_to_list(iolist_to_binary(L))).


%% @doc Convert (almost) any value to an atom.
-spec to_binary(term()) -> binary().
to_binary(undefined) -> <<>>;
to_binary(A) when is_atom(A) -> atom_to_binary(A, utf8);
to_binary(B) when is_binary(B) -> B;
to_binary(I) when is_integer(I) -> integer_to_binary(I);
to_binary(F) when is_float(F) -> to_binary(to_list(F));
to_binary(L) when is_list(L) -> iolist_to_binary(L);
to_binary({trans, [ {_, B} | _ ] = Tr}) when is_binary(B) ->
    case proplists:get_value(en, Tr) of
        undefined -> B;
        V -> to_binary(V)
    end;
to_binary({{_, _, _}, {_, _, _}} = DT) ->
    to_binary(z_dateformat:format(DT, "Y-m-d H:i:s", []));
to_binary({trans, []}) ->
    <<>>.

%% Specific Zotonic callback, please keep here.
to_binary({trans, _} = Tr, Context) -> to_binary(z_trans:lookup_fallback(Tr, Context));
to_binary(A, _Context) -> to_binary(A).


%% @doc Convert (almost) any value to an integer.
-spec to_integer(term()) -> integer() | undefined.
to_integer(undefined) -> undefined;
to_integer("") -> undefined;
to_integer(<<>>) -> undefined;
to_integer(A) when is_atom(A) -> to_integer(atom_to_list(A));
to_integer(B) when is_binary(B) -> binary_to_integer(B);
to_integer(I) when is_integer(I) -> I;
to_integer(F) when is_float(F) -> erlang:round(F);
to_integer([C]) when is_integer(C) andalso (C > $9 orelse C < $0) -> C;
to_integer(L) when is_list(L) -> list_to_integer(L).

%% @doc Convert (almost) any value to a float.
-spec to_float(term()) -> float() | undefined.
to_float(undefined) -> undefined;
to_float([]) -> undefined;
to_float(A) when is_atom(A) -> to_float(atom_to_list(A));
to_float(B) when is_binary(B) -> to_float(binary_to_list(B));
to_float(I) when is_integer(I) -> I + 0.0;
to_float(F) when is_float(F) -> F;
to_float(L) when is_list(L) ->
    case lists:member($., L) of
        true -> list_to_float(L);
        false -> list_to_float(L++".0")  %% list_to_float("1") gives a badarg
    end.


%% @doc Quite loose conversion of values to boolean
-spec to_bool(term()) -> boolean().
to_bool("false") -> false;
to_bool("FALSE") -> false;
to_bool("n") -> false;
to_bool("N") -> false;
to_bool("no") -> false;
to_bool("NO") -> false;
to_bool(<<"false">>) -> false;
to_bool(<<"FALSE">>) -> false;
to_bool(<<"n">>) -> false;
to_bool(<<"N">>) -> false;
to_bool(<<"no">>) -> false;
to_bool(<<"NO">>) -> false;
to_bool("disabled") -> false;
to_bool(<<"disabled">>) -> false;
to_bool("DISABLED") -> false;
to_bool(<<"DISABLED">>) -> false;
to_bool([0]) -> false;
to_bool(V) -> to_bool_strict(V).

% @doc Convert values to boolean values according to the Django rules
-spec to_bool_strict(term()) -> boolean().
to_bool_strict(undefined) -> false;
to_bool_strict(false) -> false;
to_bool_strict(0) -> false;
to_bool_strict(0.0) -> false;
to_bool_strict(<<>>) -> false;
to_bool_strict(<<0>>) -> false;
to_bool_strict([]) -> false;
to_bool_strict({rsc_list, []}) -> false;
to_bool_strict({trans, []}) -> false;
to_bool_strict({trans, Tr}) ->
    lists:any(
        fun({_, V}) -> V =/= <<>> end,
        Tr);
to_bool_strict("0") -> false;
to_bool_strict(<<"0">>) -> false;
to_bool_strict(M) when is_map(M) ->
    maps:size(M) =/= 0;
to_bool_strict({{9999,M,D},{H,I,S}}) % ?ST_JUTTEMIS
    when is_integer(M), is_integer(D),
         is_integer(H), is_integer(I), is_integer(S),
         M >= 1, M =< 12, D >= 1, D =< 31, H >= 0, H =< 23,
         I >= 0, I =< 59, S >= 0, S =< 60 -> false;
to_bool_strict(_) -> true.


%% @doc Convert a local date time to utc
-spec to_utc( z_dateformat:datetime() | undefined ) -> z_dateformat:datetime() | undefined.
to_utc(undefined) ->
    undefined;
to_utc({{9999,_,_}, _}) ->
    ?ST_JUTTEMIS;
to_utc(D) ->
    case catch calendar:local_time_to_universal_time_dst(D) of
        [] -> D;    % This time never existed in the local time, just take it as-is
        [UTC] -> UTC;
        [DstUTC, _UTC] -> DstUTC;
        {'EXIT', _} -> D
    end.


%% @doc Convert a utc date time to local
-spec to_localtime( z_dateformat:datetime() | undefined ) -> z_dateformat:datetime() | undefined.
to_localtime(undefined) ->
    undefined;
to_localtime({{9999,_,_},_}) ->
    ?ST_JUTTEMIS;
to_localtime(D) ->
    case catch calendar:universal_time_to_local_time(D) of
        {'EXIT', _} -> D;
        LocalD -> LocalD
    end.

%% @doc Convert an input to a (universal) datetime, using to_date/1 and
%% to_time/1.  If the input is a string, it is expected to be in iso
%% 8601 format, although it can also handle timestamps without time
%% zones. The time component of the datatime is optional.
-spec to_datetime( z_dateformat:datetime() | calendar:date() | binary() | string() | undefined ) -> z_dateformat:datetime() | undefined.
to_datetime(undefined) -> undefined;
to_datetime({{_,_,_},{_,_,_}} = DT) -> DT;
to_datetime({_,_,_} = D) -> {D, {0,0,0}};
to_datetime(B) when is_binary(B) ->
    to_datetime(binary_to_list(B));
to_datetime("") ->
    undefined;
to_datetime(L) when is_list(L) ->
    try
      case string:tokens(L, " T") of
            [Date,Time] ->
                WithTZ = fun(Tm, Tz, Mul) ->
                                 TZTime = to_time(Tz),
                                 Add = calendar:datetime_to_gregorian_seconds({{0,1,1},TZTime}),
                                 Secs = calendar:datetime_to_gregorian_seconds({to_date(Date), to_time(Tm)}),
                                 calendar:gregorian_seconds_to_datetime(Secs+(Mul*Add))
                         end,
                case string:tokens(Time, "+") of
                    [Time1, TZ] ->
                        %% Timestamp with positive time zone
                        WithTZ(Time1, TZ, -1);
                    _ ->
                        case string:tokens(Time, "-") of
                            [Time1, TZ] ->
                                %% Timestamp with negative time zone
                                WithTZ(Time1, TZ, 1);
                            _ ->
                                case lists:reverse(Time) of
                                    [$Z|Rest] ->
                                        %% Timestamp ending on Z (= UTC)
                                        {to_date(Date), to_time(lists:reverse(Rest))};
                                    _ ->
                                        %% Timestamp without time zone
                                        {to_date(Date), to_time(Time)}
                                end
                        end
                end;
            [Date] ->
                {to_date(Date), {0,0,0}}
        end
    catch
        _:_ -> undefined
    end.

%% @doc Convert an input to a date. Input is expected to be YYYY-MM-DD
%% or YYYY/MM/DD.
-spec to_date( z_dateformat:date() | binary() | string() | undefined ) -> z_dateformat:date() | undefined.
to_date(undefined) -> undefined;
to_date({_,_,_} = D) -> D;
to_date(B) when is_binary(B) ->
    to_date(binary_to_list(B));
to_date("") -> undefined;
to_date(L) when is_list(L) ->
    case string:tokens(L, "-/") of
        [D,M,Y] when length(Y) =:= 4 ->
            {to_integer(Y),to_integer(M),to_integer(D)};
        [Y,M,D] ->
            {to_integer(Y),to_integer(M),to_integer(D)};
        _ ->
            undefined
    end.

%% @doc Convert an input to a time. Input is expected to be HH:MM:SS
%% or HH.MM.SS.
-spec to_time( calendar:time() | binary() | string() | undefined ) -> calendar:time() | undefined.
to_time(undefined) -> undefined;
to_time({_,_,_} = D) -> D;
to_time(B) when is_binary(B) ->
    to_time(binary_to_list(B));
to_time("") -> undefined;
to_time([H1,H2,M1,M2]) ->
    to_time([H1,H2,$:,M1,M2]);
to_time(L) when is_list(L) ->
    [H,I,S|_] = lists:flatten([[to_integer(X) ||X <-  string:tokens(L, ":.")], 0, 0]),
    {H,I,S}.

%% @doc Convert a datetime (in universal time) to an ISO time string.
-spec to_isotime( z_dateformat:datetime() ) -> binary().
to_isotime(DateTime) ->
    z_dateformat:format(DateTime, "x-m-d\\TH:i:s\\Z", []).


%%
%% @doc Convert an Erlang structure to a format that can be serialized by mochijson.
%%

%% Simple values
to_json(undefined) ->
    null;
to_json(X) when is_atom(X) ->
    X;
to_json(X) when is_integer(X) ->
    X;
to_json(X) when is_float(X) ->
    X;
to_json(X) when is_binary(X) ->
    X;

%% Tuple values
to_json({{Y,M,D},{H,I,S}} = DateTime)
    when is_integer(Y), is_integer(M), is_integer(D),
         is_integer(H), is_integer(I), is_integer(S) ->
    z_dateformat:format(DateTime, "c", [{utc,DateTime}]);
to_json({array, X}) ->
    %% Explicit request for array (to prevent string conversion for some lists)
    {array, [to_json(V) || V <- X]};
to_json({struct, X}) ->
    {struct, X};
to_json({X, Y}) ->
    {struct, to_json_struct([{X, Y}])};
to_json(X) when is_tuple(X) ->
    {array, [to_json(V) || V <- tuple_to_list(X)]};

%% List values
to_json([{X, Y}]) when is_atom(X) ->
    {struct, to_json_struct([{X, Y}])};
to_json([{X, Y} | Z]) when is_atom(X) ->
    {struct, to_json_struct([{X, Y} | Z])};
to_json(X) when is_list(X) ->
    case z_string:is_string(X) of
        true ->
            X;
        false ->
            {array, [to_json(V) || V <- X]}
    end.

%% Handle structs specially
to_json_struct([]) ->
    [];
to_json_struct([{X,Y}|T]) ->
    [{to_json_struct_key(X), to_json(Y)} | to_json_struct(T)].
to_json_struct_key(X) when is_atom(X) orelse is_integer(X) orelse is_binary(X) ->
    X;
to_json_struct_key(X) when is_list(X) ->
    case z_string:is_string(X) of
        true ->
            X;
        false ->
            invalid_key
    end;
to_json_struct_key(_) ->
    invalid_key.



ip_to_list({IP,Port}) when is_tuple(IP), is_integer(Port) ->
    ip_to_list(IP);
ip_to_list({N1,N2,N3,N4} ) ->
    lists:flatten([integer_to_list(N1), $., integer_to_list(N2), $., integer_to_list(N3), $., integer_to_list(N4)]);
ip_to_list({_K1,_K2,_K3,_K4,_K5,_K6,_K7,_K8} = IPv6) ->
    L = lists:map(fun(0) -> "";
                     (N) -> io_lib:format("~.16b", [N])
                  end,
                  tuple_to_list(IPv6)),
    lists:flatten(string:join(L, ":")).


%% Taken from egeoip (http://code.google.com/p/egeoip/source/browse/trunk/egeoip/src/egeoip.erl?r=19)
%% @spec ip_to_long(Address) -> {ok, integer()} | {error, badmatch}
%% @doc Convert an IP address from a string, IPv4 tuple or IPv6 tuple to the
%%      big endian integer representation.
ip_to_long({B3, B2, B1, B0}) ->
    {ok, (B3 bsl 24) bor (B2 bsl 16) bor (B1 bsl 8) bor B0};
ip_to_long({W7, W6, W5, W4, W3, W2, W1, W0}) ->
    {ok, (W7 bsl 112) bor (W6 bsl 96) bor (W5 bsl 80) bor (W4 bsl 64) bor
	(W3 bsl 48) bor (W2 bsl 32) bor (W1 bsl 16) bor W0};
ip_to_long(_) ->
    {error, badmatch}.


%% @doc Convert long int to IP address tuple. FIXME: ipv6
long_to_ip(L) ->
    {ok, {(L band (255 bsl 24)) bsr 24,
          (L band (255 bsl 16)) bsr 16,
          (L band (255 bsl 8)) bsr 8,
          L band 255}}.


%% @doc Convert json from facebook favour to an easy to use format for zotonic templates.
convert_json({K, V}) when is_binary(K) ->
    {z_convert:to_atom(K), convert_json(V)};
convert_json({struct, PropList}) when is_list(PropList) ->
    convert_json(PropList);
convert_json(L) when is_list(L) ->
    [convert_json(V) || V <- L];
convert_json(V) ->
    V.

unicode_to_utf8(List) when is_list(List) -> lists:flatmap(fun unicode_to_utf8/1, List);
unicode_to_utf8(Ch) -> char_to_utf8(Ch).

char_to_utf8(Ch) when is_integer(Ch), Ch >= 0 ->
    if Ch < 128 ->
	    %% 0yyyyyyy
	    [Ch];
       Ch < 16#800 ->
	    %% 110xxxxy 10yyyyyy
	    [16#C0 + (Ch bsr 6),
	     128+(Ch band 16#3F)];
       Ch < 16#10000 ->
	    %% 1110xxxx 10xyyyyy 10yyyyyy
	    if Ch < 16#D800; Ch > 16#DFFF, Ch < 16#FFFE ->
		    [16#E0 + (Ch bsr 12),
		     128+((Ch bsr 6) band 16#3F),
		     128+(Ch band 16#3F)];
               true -> [$?]
	    end;
       Ch < 16#200000 ->
	    %% 11110xxx 10xxyyyy 10yyyyyy 10yyyyyy
	    [16#F0+(Ch bsr 18),
	     128+((Ch bsr 12) band 16#3F),
	     128+((Ch bsr 6) band 16#3F),
	     128+(Ch band 16#3F)];
       Ch < 16#4000000 ->
	    %% 111110xx 10xxxyyy 10yyyyyy 10yyyyyy 10yyyyyy
	    [16#F8+(Ch bsr 24),
	     128+((Ch bsr 18) band 16#3F),
	     128+((Ch bsr 12) band 16#3F),
	     128+((Ch bsr 6) band 16#3F),
	     128+(Ch band 16#3F)];
       Ch < 16#80000000 ->
	    %% 1111110x 10xxxxyy 10yyyyyy 10yyyyyy 10yyyyyy 10yyyyyy
	    [16#FC+(Ch bsr 30),
	     128+((Ch bsr 24) band 16#3F),
	     128+((Ch bsr 18) band 16#3F),
	     128+((Ch bsr 12) band 16#3F),
	     128+((Ch bsr 6) band 16#3F),
	     128+(Ch band 16#3F)];
       true -> [$?]
    end.
