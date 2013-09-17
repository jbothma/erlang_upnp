-module(bob).

-export([start/0]).

-define(UPNP_DISCOVER,
    "M-SEARCH * HTTP/1.1\r\n"
    "Host: 239.255.255.250:1900\r\n"
    "Man: \"ssdp:discover\"\r\n"
    "ST: upnp:rootdevice\r\n"
    "MX: 3\r\n\r\n").

-include_lib("xmerl/include/xmerl.hrl").

start() ->
    application:start(inets),
    Opts = [{multicast_loop, false},
            {multicast_if, {0,0,0,0}},
            {multicast_ttl, 4},
            {reuseaddr, true}],
    {ok, S} = gen_udp:open(1900, Opts),
    send_discover(S),
    loop(S).

send_discover(S) ->
    gen_udp:send(S, {239,255,255,250}, 1900, ?UPNP_DISCOVER).

loop(S) ->
    receive
        {udp, S, _, _, Msg} ->
            handle_msg(Msg),
            loop(S)
    after 30000 ->
            gen_udp:close(S)
    end.

handle_msg(Msg) ->
    HeadsProplist = parse_heads(Msg),
    Date     = proplists:get_value("date", HeadsProplist),
    USN      = proplists:get_value("usn", HeadsProplist),
    Location = proplists:get_value("location", HeadsProplist),
    DescriptionXML = fetch_description(Location),
    {DescriptionXMErl, _Rest} = xmerl_scan:string(DescriptionXML),
    NameXPath = "//friendlyName/text()",
    [NameXMLText] = xmerl_xpath:string(NameXPath, DescriptionXMErl),
    io:format("~s~n  Name    : ~s~n  USN     : ~s~n  Location: ~s~n~n",
              [Date, NameXMLText#xmlText.value, USN, Location]).


parse_heads(HeadsStr) ->
    [_|SplitLines] = re:split(HeadsStr, "[\r\n]+", [multiline, trim]),
    Fun = fun(Line) ->
                  [Key, Val] = re:split(Line, ": ?", [{parts, 2},
                                                      {return, list}]),
                  {string:to_lower(Key), Val}
          end,
    lists:map(Fun, SplitLines).

fetch_description(Location) ->
    {ok, {{"HTTP/1.1", 200, "OK"}, _Heads, Body}} = httpc:request(Location),
    Body.
