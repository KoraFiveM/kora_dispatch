# Converted from the communitybot legacy tests by kora-qa-panel/scripts/convert-legacy.mjs.
# The """ block under each Scenario is the original test text, verbatim. Review before applying.
Feature: kora_dispatch — Police & EMS

  @kora_dispatch @checklist @checklist:kora_dispatch:access-on-duty @cat:police-and-ems @needs:admin
  Scenario: Feed only for on-duty emergency services
    """
    Checklist test: Go on duty (/setjob <id> police 4, /police-duty); feed works. Civilians or off-duty players see nothing.
    """
    Given my job is "police" at grade 4
    And I am on duty
    When I run the command "/dispatchtest 1"
    Then I confirm: the dispatch alert feed shows a card for the new call
    When I run the command "/police-duty"
    Then I should be off duty
    When I run the command "/dispatchtest 1"
    Then I confirm: I see no dispatch feed card while off duty
    When I manually: ask a Mod to set my job to unemployed
    Then I confirm: I see no dispatch feed as a civilian

  @kora_dispatch @checklist @checklist:kora_dispatch:dispatchtest @cat:police-and-ems @needs:admin
  Scenario: /dispatchtest raises a call
    """
    Checklist test: Admin: /dispatchtest 1|2|3 (and optional 'ems') raises critical/high/routine call to your service; feed card appears with tone.
    """
    Given my job is "police"
    And I am on duty
    When I run the command "/dispatchtest 1"
    Then I confirm: a critical call is raised for my service
    And I confirm: a feed card appears with an alert tone
    When I run the command "/dispatchtest 2"
    Then I confirm: a high call is raised for my service
    When I run the command "/dispatchtest 3"
    Then I confirm: a routine call is raised for my service
    When I run the command "/dispatchtest 1 ems"
    Then I confirm: the call goes to the EMS service instead of mine

  @kora_dispatch @checklist @checklist:kora_dispatch:feed-card @cat:police-and-ems @needs:admin
  Scenario: Alert feed card
    """
    Checklist test: Card shows severity edge, code, title, elapsed time and unit count; does not steal mouse or camera.
    """
    Given my job is "police"
    And I am on duty
    When I run the command "/dispatchtest 1"
    Then I confirm: the feed card shows a severity edge, code, title, elapsed time and unit count
    And I confirm: the feed does not steal my mouse or camera

  @kora_dispatch @checklist @checklist:kora_dispatch:select-calls @cat:police-and-ems @needs:admin
  Scenario: Page Up/Down select calls
    """
    Checklist test: Press Page Up/Page Down to move selection; key hints appear; keep pressing to scroll into history.
    """
    Given my job is "police"
    And I am on duty
    When I run the command "/dispatchtest 1"
    And I manually: press Page Up and Page Down to move the selection
    Then I confirm: the selection moves and key hints appear
    When I manually: keep pressing Page Down
    Then I confirm: the selection scrolls into history

  @kora_dispatch @checklist @checklist:kora_dispatch:respond-home @cat:police-and-ems @needs:admin
  Scenario: Home key: accept / on scene / clear
    """
    Checklist test: Press Home: en route (GPS route on minimap), again on scene, again clear and route removed. With nothing selected it takes the newest call.
    """
    Given my job is "police"
    And I am on duty
    When I run the command "/dispatchtest 1"
    And I manually: press Home with no call selected
    Then I confirm: the newest call is taken and I am en route with a GPS route on my minimap
    When I manually: press Home again
    Then I confirm: my status changes to on scene
    When I manually: press Home again
    Then I confirm: the call is cleared and the GPS route is removed from my minimap

  @kora_dispatch @checklist @checklist:kora_dispatch:hide-feed-end @cat:police-and-ems @needs:admin
  Scenario: End key hides/shows feed
    """
    Checklist test: Press End: feed collapses to 'Dispatch muted' chip; again restores. With tablet open End closes the tablet.
    """
    Given my job is "police"
    And I am on duty
    When I run the command "/dispatchtest 1"
    And I manually: press End
    Then I confirm: the feed collapses to a 'Dispatch muted' chip
    When I manually: press End again
    Then I confirm: the feed is restored
    When I press the "F9" key
    Then the "qbdispatch:tablet" app opens
    When I manually: press End
    Then I confirm: the tablet closes

  @kora_dispatch @checklist @checklist:kora_dispatch:tablet-f9 @cat:police-and-ems
  Scenario: F9 dispatch tablet
    """
    Checklist test: Press F9 to open the tablet with map; F9 or X closes it and returns mouse control.
    """
    Given my job is "police"
    And I am on duty
    When I press the "F9" key
    Then the "qbdispatch:tablet" app opens
    And I confirm: the tablet shows a map
    When I press the "F9" key
    Then I confirm: the tablet closes and I get mouse control back
    When I press the "F9" key
    Then the "qbdispatch:tablet" app opens
    When I manually: press X
    Then I confirm: the tablet closes and I get mouse control back

  @kora_dispatch @checklist @checklist:kora_dispatch:tablet-map @cat:police-and-ems @needs:admin
  Scenario: Tablet map pan/zoom/centre
    """
    Checklist test: Drag to pan, scroll to zoom, Crosshair button recentres; call markers and your own filled marker are shown.
    """
    Given my job is "police"
    And I am on duty
    When I run the command "/dispatchtest 1"
    And I press the "F9" key
    Then the "qbdispatch:tablet" app opens
    When I manually: drag the map to pan it and scroll to zoom
    Then I confirm: the map pans and zooms
    When I manually: click the Crosshair button
    Then I confirm: the map recentres
    And I confirm: call markers and my own filled marker are shown

  @kora_dispatch @checklist @checklist:kora_dispatch:tablet-filters @cat:police-and-ems @needs:admin
  Scenario: Active/Mine/History filters and search
    """
    Checklist test: Switch filters and use search box; list paginates 8 per page; changing filter resets to page 1.
    """
    Given my job is "police"
    And I am on duty
    When I run the command "/dispatchtest 1"
    And I press the "F9" key
    And I manually: switch between the Active, Mine and History filters
    Then I confirm: the list changes with each filter
    When I manually: type in the search box
    Then I confirm: the list is filtered by my search
    And I confirm: the list paginates 8 per page
    When I manually: go to page 2 and change the filter
    Then I confirm: the list resets to page 1

  @kora_dispatch @checklist @checklist:kora_dispatch:tablet-detail @cat:police-and-ems @needs:admin
  Scenario: Call detail, Accept/Detach, Route here
    """
    Checklist test: Select a call: detail panel shows data fields and responding units; Accept, Detach and 'Route here' (sets GPS) work.
    """
    Given my job is "police"
    And I am on duty
    When I run the command "/dispatchtest 1"
    And I press the "F9" key
    And I manually: select a call in the list
    Then I confirm: the detail panel shows the data fields and responding units
    When I manually: click Accept
    Then I confirm: I am added as a responding unit
    When I manually: click Detach
    Then I confirm: I am removed from the responding units
    When I manually: click Route here
    Then I confirm: a GPS route to the call is set on my minimap

  @kora_dispatch @checklist @checklist:kora_dispatch:colleague-positions @cat:police-and-ems
  Scenario: On-duty colleagues on map
    """
    Checklist test: Two on-duty players see each other on the tablet map with callsign and vehicle icon (car/heli) updating.
    """
    Given my job is "police"
    And I am on duty
    When I manually: ask a second player to go on duty as police
    And I press the "F9" key
    Then the "qbdispatch:tablet" app opens
    And I confirm: I see the other player on the tablet map with callsign and vehicle icon (car/heli)
    And I confirm: their marker updates as they move
    And I confirm: the second player sees me on their tablet map the same way

  @kora_dispatch @checklist @checklist:kora_dispatch:max-active-calls @cat:police-and-ems
  Scenario: One active call at a time
    """
    Checklist test: While en route to one call, try to accept another; refused with 'already en route to a call'.
    """
    Given my job is "police"
    And I am on duty
    When I manually: ask a second player to raise two dispatch calls for police (e.g. /dispatchtest 1 leo twice)
    And I manually: press Home to accept the first call and go en route
    And I manually: select the second call and press Home to accept it
    Then I should see a notification containing "already en route to a call"

  @kora_dispatch @checklist @checklist:kora_dispatch:service-separation @cat:police-and-ems
  Scenario: Calls reach only their service
    """
    Checklist test: Police player does not see EMS calls and vice versa; panic F10 creates 10-99 to police and 10-52 to EMS.
    """
    Given my job is "police"
    And I am on duty
    When I manually: ask a second player to raise an EMS call and a police call
    Then I confirm: I see the police call in my feed and do not see the EMS call
    When I manually: ask a second player who is on duty as ambulance to check their feed
    Then I confirm: the other player sees the EMS call and does not see the police call
    When I press the "F10" key
    Then I confirm: a 10-99 call is created for police
    When I manually: ask a second player on duty as ambulance to press F10
    Then I confirm: the other player sees a 10-52 call created for EMS

  @kora_dispatch @checklist @checklist:kora_dispatch:severity-fade @cat:police-and-ems
  Scenario: Priority lifetime and fade
    """
    Checklist test: Routine call fades after ~70s and expires at 2 min, critical lasts 10 min; expired calls remain in History.
    """
    Given my job is "police"
    And I am on duty
    When I manually: raise one routine (priority 3) call and one critical (priority 1) call with /dispatchtest and watch the feed
    And I wait 70 seconds
    Then I confirm: the routine call has started to fade
    When I wait 60 seconds
    Then I confirm: the routine call has expired from the live feed
    And I confirm: the critical call is still live (it lasts 10 minutes)
    When I press the "F9" key
    Then the "qbdispatch:tablet" app should be open
    When I manually: open History in the tablet
    Then I confirm: the expired routine call is still listed in History

  @kora_dispatch @checklist @checklist:kora_dispatch:map-blips @cat:police-and-ems
  Scenario: Map blips capped to urgent calls
    """
    Checklist test: Raise more than 4 calls; only the 4 most urgent get native map blips (Dispatch category); accepted call gets GPS route.
    """
    Given my job is "police"
    And I am on duty
    When I manually: raise 5 or more calls of differing priority with /dispatchtest
    And I manually: open the map and look at the Dispatch blip category
    Then I confirm: only the 4 most urgent calls have native map blips under the Dispatch category
    When I manually: accept a call with Home
    Then I confirm: a GPS route is set to the accepted call

  @kora_dispatch @checklist @checklist:kora_dispatch:per-service-colour @cat:police-and-ems
  Scenario: Per-service accent colour
    """
    Checklist test: Blue as police, red as EMS; change job/duty (/ems-duty) and the UI recolours without restart.
    """
    Given my job is "police"
    And I am on duty
    When I press the "F9" key
    Then the "qbdispatch:tablet" app should be open
    And I confirm: the dispatch UI accent is blue
    When I run the command "/ems-duty"
    And I manually: switch to an EMS job and go on duty without restarting the resource
    Then I confirm: the dispatch UI is now recoloured red

  @kora_dispatch @checklist @checklist:kora_dispatch:dispatchclear @cat:police-and-ems @needs:admin
  Scenario: /dispatchclear command
    """
    Checklist test: Admin: run /dispatchclear; every live call on your service is closed and removed from feed and map.
    """
    Given my job is "police"
    And I am on duty
    When I manually: raise several live calls for my service with /dispatchtest
    And I run the command "/dispatchclear"
    Then I should see a notification containing "Closed"
    And I confirm: every live call on my service is removed from the feed
    And I confirm: the call blips are removed from the map

  @kora_dispatch @checklist @checklist:kora_dispatch:dispatchcoords @cat:police-and-ems
  Scenario: /dispatchcoords command
    """
    Checklist test: Run /dispatchcoords; your world position and projected tablet map pixel are printed.
    """
    When I run the command "/dispatchcoords"
    Then I confirm: my world position and the projected tablet map pixel are printed

  @kora_dispatch @checklist @checklist:kora_dispatch:real-triggers @cat:police-and-ems
  Scenario: Automatic crime triggers
    """
    Checklist test: /backup (10-78), civilian gunshots (10-31), occupied car jacking (10-16), /911e text (EMS p1), death 10-52, revive closes the call.
    """
    Given my job is "police"
    And I am on duty
    When I run the command "/backup"
    Then I confirm: a 10-78 call appears in the feed
    When I manually: ask a second player (civilian) to fire a gun
    Then I confirm: a 10-31 call appears in my feed
    When I manually: ask a second player to jack an occupied car
    Then I confirm: a 10-16 call appears in my feed
    When I manually: ask a second player to run /911e with a text message
    Then I confirm: an EMS priority 1 call is created with that text
    When I manually: ask a second player to die
    Then I confirm: a 10-52 call is created
    When I manually: ask a second player to revive them
    Then I confirm: the 10-52 call is closed

  @kora_dispatch @checklist @checklist:kora_dispatch:onduty-no-self-alert @cat:police-and-ems
  Scenario: On-duty police gunfire is ignored
    """
    Checklist test: Fire a gun as on-duty police; no Shots Fired call is created.
    """
    Given my job is "police"
    And I am on duty
    And I have a "weapon_pistol" equipped with 30 ammo
    When I manually: fire the gun a few times
    Then I confirm: no Shots Fired call appears in the dispatch feed

  @kora_dispatch @checklist @checklist:kora_dispatch:keybinds-rebind @cat:police-and-ems @manual
  Scenario: Keys rebindable
    """
    Checklist test: Open FiveM Settings > Key Bindings > FiveM and rebind Home/End/Page keys/F9; new keys work.
    """
    When I manually: open FiveM Settings > Key Bindings > FiveM
    And I manually: rebind the dispatch Home, End, Page Up, Page Down and F9 keys to other keys
    Then I confirm: the new keys work for respond, toggle, previous, next and the tablet

  @kora_dispatch @checklist @checklist:kora_dispatch:legacy-alert-compat @cat:police-and-ems @needs:admin @manual
  Scenario: Legacy exports.kora_core:alert mirrored
    """
    Checklist test: A script firing qbcore:server:dispatchAlert / kora_core alert produces a real dispatch call in the feed.
    """
    When I manually: as an admin, use /runcode to run a snippet that calls exports.kora_core:alert (or triggers qbcore:server:dispatchAlert on the server) with a test message
    Then I confirm: a real dispatch call appears in my dispatch feed
    And I confirm: the same call is listed in the F9 tablet
