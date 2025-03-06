globals [
  battlefield-width
  battlefield-height

  ;; Two separate Q-tables:
  ;;  - One for Israeli side
  ;;  - One for Egyptian side
  q-table-israeli
  q-table-egyptian

  ;; Learning parameters
  alpha
  gamma
  epsilon

  ;; Chance that a shooting event actually kills the target (0 to 1)
  kill-prob

  ;; Group IDs to keep track of which turtles spawn together
  group-counter

  ;; Patches that define the "Chinese Farm" area
  chinese-farm-patches
  chinese-farm-center

  ;; Strategic locations - NEW
  strategic-locations
]

breed [israeli-tanks israeli-tank]
breed [egyptian-tanks egyptian-tank]
breed [infantry soldier]


turtles-own [
  state
  action
  team
  group-id
  defense-center  ;; Used for Egyptian defensive positioning
]

;------------------------------------------------
; SETUP PROCEDURES
;------------------------------------------------
to setup
  clear-all
  set battlefield-width 100
  set battlefield-height 100
  resize-world 0 (battlefield-width - 1) 0 (battlefield-height - 1)
  set-patch-size 5
  set alpha 0.1
  set gamma 0.9
  set epsilon 0.5
  set kill-prob 0.5
  set q-table-israeli []
  set q-table-egyptian []
  set group-counter 0
  set chinese-farm-patches []
  set strategic-locations []
  setup-terrain
  setup-strategic-locations ;; NEW
  setup-units
  reset-ticks
end

to setup-terrain
  ;; Set the entire battlefield to desert
  ask patches [
    set terrain-type "desert-west"
    set pcolor yellow
    set is-strategic false ;; NEW: initialize strategic flag
  ]
  ;; Add a vertical blue line (for visual reference)
  ask patches with [pxcor <= 20 and pxcor >= 19] [
    set pcolor blue
  ]
  ;; Define the Chinese Farm as a rectangle to the right of the blue line
  ask patches with [pxcor > 20 and pxcor <= 60 and pycor >= 20 and pycor <= 80] [
    set terrain-type "chinese-farm"
    set pcolor green
    set captured-by "none"
  ]
  set chinese-farm-patches patches with [terrain-type = "chinese-farm"]
  ;; Set the center of the Chinese Farm
  let center-x 40
  let center-y 50
  set chinese-farm-center patch center-x center-y
  ;; Add roads
  ask patches with [pycor = 30 and pxcor > 20] [
    set terrain-type "road"
    set pcolor gray
  ]
  ask patches with [pxcor = 40] [
    set terrain-type "road"
    set pcolor gray
  ]
end

;; NEW: Setup strategic locations within the Chinese Farm
to setup-strategic-locations
  ;; Create 3 strategic locations (3x3 patches each)
  ;; Location 1: Northern high ground
  create-strategic-location 30 65

  ;; Location 2: Central crossroads
  create-strategic-location 40 40

  ;; Location 3: Southern water source
  create-strategic-location 50 25
end

;; NEW: Helper procedure to create a 3x3 strategic location
to create-strategic-location [x y]
  let location-patches patches with [
    pxcor >= (x - 1) and pxcor <= (x + 1) and
    pycor >= (y - 1) and pycor <= (y + 1) and
    terrain-type = "chinese-farm"
  ]

  ask location-patches [
    set is-strategic true
    set pcolor violet ;; Mark strategic locations with a distinctive color
  ]

  set strategic-locations (patch-set strategic-locations location-patches)
end

to setup-units
  ;; Israeli Tanks: 5 groups of 5 (total 25 tanks)
  repeat 10 [
    let cluster-x (25 + random 15)
    let cluster-y (5 + random 5)
    create-israeli-tanks 5 [
      set group-id group-counter
      set team "israeli"
      set shape "circle"
      set color 135
      setxy cluster-x cluster-y
      set state (list xcor ycor)
      set action ""
    ]
    set group-counter group-counter + 1
  ]
  ;; Egyptian Tanks: 5 groups of 5 (total 25 tanks)
  repeat 5 [
    ;; Western border tanks
    let cluster-x-west 21
    let cluster-y-west (20 + random 60)
    create-egyptian-tanks 5 [
      set group-id group-counter
      set team "egyptian"
      set shape "circle"
      set color 25
      setxy cluster-x-west cluster-y-west
      set state (list xcor ycor)
      set action "hold-position"
      set size 1.5
    ]
    set group-counter group-counter + 1
    ;; Southern border tanks
    let cluster-x-south (21 + random 39)
    let cluster-y-south 20
    create-egyptian-tanks 5 [
      set group-id group-counter
      set team "egyptian"
      set shape "circle"
      set color 25
      setxy cluster-x-south cluster-y-south
      set state (list xcor ycor)
      set action "hold-position"
      set size 1.5
    ]
    set group-counter group-counter + 1
  ]
  ;; Israeli Infantry: 5 groups of 5 (total 25 infantry)
  repeat 5 [
    let cluster-x (25 + random 15)
    let cluster-y (5 + random 5)
    create-infantry 5 [
      set group-id group-counter
      set team "israeli"
      set shape "person"
      set color 0
      setxy cluster-x cluster-y
      set state (list xcor ycor)
      set action ""
    ]
    set group-counter group-counter + 1
  ]
  ;; Egyptian Infantry: 5 groups of 5 (total 25 infantry)
  repeat 5 [
    ;; Western border infantry
    let cluster-x-west 21
    let cluster-y-west (20 + random 60)
    create-infantry 5 [
      set group-id group-counter
      set team "egyptian"
      set shape "person"
      set color 15
      setxy cluster-x-west cluster-y-west
      set state (list xcor ycor)
      set action "hold-position"
      set size 1.5
    ]
    set group-counter group-counter + 1
    ;; Eastern border infantry
    let cluster-x-east 60
    let cluster-y-east (20 + random 60)
    create-infantry 5 [
      set group-id group-counter
      set team "egyptian"
      set shape "person"
      set color 15
      setxy cluster-x-east cluster-y-east
      set state (list xcor ycor)
      set action "hold-position"
      set size 1.5
    ]
    set group-counter group-counter + 1
  ]
end

;------------------------------------------------
; MAIN LOOP
;------------------------------------------------
to go
  ask israeli-tanks [ q-learn-move-israeli ]
  ask egyptian-tanks [ q-learn-move-egyptian ]
  ask infantry with [team = "israeli"] [ q-learn-move-israeli-infantry ]
  ask infantry with [team = "egyptian"] [ q-learn-move-egyptian-infantry ]
  check-shooting
  capture-chinese-farm
  reinforce-chinese-farm
  check-win-condition
  show (word "Israeli Units: " count turtles with [team = "israeli"])
  show (word "Egyptian Units: " count turtles with [team = "egyptian"])
  tick
end

;------------------------------------------------
; Q-LEARNING FOR ISRAELI UNITS
;------------------------------------------------
to q-learn-move-israeli
  let s (list xcor ycor)
  let a choose-action-israeli s
  let oldx xcor
  let oldy ycor

  ; Check if unit is stuck (no movement for several ticks)
  if (distancexy oldx oldy) < 0.1 and random-float 1 < 0.3 [
    ; Force a random movement to break out of being stuck
    set heading random 360
    fd 1
  ]

  ;; MODIFIED: Check for nearby strategic locations
  let nearby-strategic-patches strategic-locations in-radius 15
  ifelse any? nearby-strategic-patches and random-float 1 < 0.7 [
    ;; If strategic locations are nearby, prioritize moving toward them
    let target min-one-of nearby-strategic-patches [distance myself]
    if target != nobody [
      face target
      fd 1.5 ;; Move faster toward strategic locations
    ]
  ][
    ;; Original movement logic
    ifelse [terrain-type] of patch-here != "chinese-farm" [
      move-toward-chinese-farm
    ]
    [
      ; If we're in the Chinese Farm, check for nearby enemies
      ifelse any? turtles with [team = "egyptian"] in-radius 3 [
        ; If enemies nearby, engage them
        let target min-one-of turtles with [team = "egyptian"] [distance myself]
        if target != nobody [
          face target
          fd 1
        ]
      ]
      [
        ; If no enemies nearby, explore or capture territory
        execute-action a

        ; Try to prioritize movement to uncaptured areas
        if [captured-by] of patch-here = "israeli" [
          let uncaptured-nearby patches in-radius 5 with [terrain-type = "chinese-farm" and captured-by != "israeli"]
          if any? uncaptured-nearby [
            face min-one-of uncaptured-nearby [distance myself]
            fd 1
          ]
        ]
      ]
    ]
  ]

  ; Keep units from straying too far from their group
  if distance my-group-center > 5 [ setxy oldx oldy ]

  ; Attack nearby enemies
  ask egyptian-tanks in-radius 2 [
    if random-float 1 < kill-prob [ die ]
  ]
  ask infantry with [team = "egyptian"] in-radius 2 [
    if random-float 1 < kill-prob [ die ]
  ]

  let s2 (list xcor ycor)
  let r compute-reward s s2

  ; MODIFIED: Bonus reward for capturing territory with higher values for strategic locations
  if [terrain-type] of patch-here = "chinese-farm" and [captured-by] of patch-here != "israeli" [
    ifelse [is-strategic] of patch-here [
      set r r + 2000 ;; Much higher reward for strategic locations
      show (word "Israeli unit " who " captured a strategic location!")
    ][
      set r r + 500 ;; Regular reward for normal locations
    ]
  ]

  update-q-table-israeli s a r s2
end

;------------------------------------------------
; Q-LEARNING FOR EGYPTIAN TANKS
;------------------------------------------------
to q-learn-move-egyptian
  ; Modified to make units less likely to get stuck
  if action = "hold-position" [
    if [terrain-type] of patch-here != "chinese-farm" [
      move-toward-chinese-farm
      stop
    ]
    if (not is-list? defense-center) or (defense-center = 0) [
      set defense-center (list xcor ycor)
    ]

    ;; MODIFIED: Check for nearby strategic locations under Israeli control
    let strategic-israeli-captured strategic-locations with [captured-by = "israeli"] in-radius 20
    ifelse any? strategic-israeli-captured [
      show (word "Egyptian tank " who " detected captured strategic location!")
      set action "surround"  ;; Change action mode to allow movement
    ][
      ifelse any? turtles with [ team = "israeli" ] in-radius 10 [
        show (word "Egyptian tank " who " detected an Israeli unit!")
        set action "surround"  ; Change action mode to allow movement
      ] [
        ; Look for captured areas to reclaim - MODIFIED FOR BETTER MOVEMENT
        let israeli-captured-nearby patches in-radius 12 with [terrain-type = "chinese-farm" and captured-by = "israeli"]
        ifelse any? israeli-captured-nearby [
          show (word "Egyptian tank " who " moving to recapture territory!")
          face min-one-of israeli-captured-nearby [distance myself]
          fd 1.5  ; Increased movement speed

          ; Break out of hold position if we're trying to recapture
          if random-float 1 < 0.3 [  ; 30% chance to switch to active recapture
            set action "surround"
          ]
        ] [
          ; Random movement to avoid getting stuck
          ifelse random-float 1 < 0.7 [
            ; Stay near defense position most of the time
            rt (random 40 - 20)
            fd 0.75  ; Increased from 0.5
            if distancexy (item 0 defense-center) (item 1 defense-center) > 7 [  ; Increased radius
              face patch (item 0 defense-center) (item 1 defense-center)
              fd 1  ; More decisive movement back to position
            ]
          ] [
            ; Sometimes explore further
            rt (random 90 - 45)
            fd 1.5
          ]
        ]
        stop
      ]
    ]
  ]

  let s (list xcor ycor)
  let a choose-action-egyptian s
  let oldx xcor
  let oldy ycor

  ; Store original action value to restore it if we need to
  let original-action action

  ;; MODIFIED: Check for nearby strategic locations under Israeli control or not yet captured
  let strategic-targets strategic-locations with [captured-by = "israeli" or captured-by = "none"] in-radius 20
  ifelse any? strategic-targets and random-float 1 < 0.8 [
    ;; Prioritize recapturing strategic locations
    let target min-one-of strategic-targets [distance myself]
    if target != nobody [
      face target
      fd 2  ;; Move faster toward strategic locations
      show (word "Egyptian tank " who " moving toward strategic location!")
    ]
  ][
    let nearby-israeli-tanks israeli-tanks in-radius 10  ; Increased radius
    let nearby-israeli-infantry infantry with [team = "israeli"] in-radius 15  ; Increased radius

    ; First priority: Find Israeli forces to engage
    ifelse any? nearby-israeli-tanks or any? nearby-israeli-infantry [
      let nearest-enemy min-one-of (turtle-set nearby-israeli-tanks nearby-israeli-infantry) [ distance myself ]
      if nearest-enemy != nobody [
        set a "surround"
        face nearest-enemy
        fd 1.25  ; Increased movement speed
      ]
    ]
    [
      ; Second priority: Recapture lost territory - MODIFIED FOR BETTER MOVEMENT
      let israeli-captured patches in-radius 15 with [terrain-type = "chinese-farm" and captured-by = "israeli"]
      ifelse any? israeli-captured [
        face min-one-of israeli-captured [distance myself]
        fd 2  ; Increased from 1.5 for more decisive movement

        ; Claim territory we're standing on
        if [terrain-type] of patch-here = "chinese-farm" [
          ask patch-here [
            set captured-by "egyptian"
            set pcolor green
          ]
        ]
      ]
      [
        ; Third priority: Regular movement
        ifelse [terrain-type] of patch-here != "chinese-farm" [
          move-toward-chinese-farm
        ]
        [
          ; If we're in Chinese Farm and no enemies nearby, mix defend and exploration
          ifelse random-float 1 < 0.6 [  ; Reduced from 0.7
            execute-action "defend"
          ]
          [
            ; Increased chance of exploratory movement
            execute-action a

            ; Add some randomness to break out of stuck patterns
            if random-float 1 < 0.15 [  ; 15% chance for random movement
              rt (random 180 - 90)
              fd 1.5
            ]
          ]

          ; Relaxed group cohesion constraint - IMPORTANT FIX
          if distance my-group-center > 8 [  ; Increased from 5
            ; Don't teleport back anymore, just move toward group
            face my-group-center
            fd 1
          ]
        ]
      ]
    ]
  ]

  ; Restore original action if this was a hold-position unit, but with chance to break free
  if original-action = "hold-position" and random-float 1 < 0.85 [  ; 15% chance to escape hold position
    set action original-action
  ]

  let kills 0
  ask israeli-tanks in-radius 2 [
    if random-float 1 < kill-prob [
      die
      set kills kills + 1
    ]
  ]
  ask infantry with [team = "israeli"] in-radius 2 [
    if random-float 1 < kill-prob [
      die
      set kills kills + 1
    ]
  ]

  let s2 (list xcor ycor)
  let r compute-reward s s2

  ; MODIFIED: Extra reward for kills and recapturing territory with higher values for strategic locations
  set r (r + 50 * kills)
  if [terrain-type] of patch-here = "chinese-farm" and [captured-by] of patch-here = "israeli" [
    ifelse [is-strategic] of patch-here [
      set r r + 2000  ;; Much higher reward for recapturing strategic locations
      show (word "Egyptian tank " who " recaptured a strategic location!")
    ][
      set r r + 500  ;; Regular reward for normal locations
    ]
  ]

  update-q-table-egyptian s a r s2
end

;------------------------------------------------
; Q-LEARNING FOR ISRAELI INFANTRY
;------------------------------------------------
to q-learn-move-israeli-infantry
  let s (list xcor ycor)
  let a choose-action-israeli s
  let oldx xcor
  let oldy ycor

  ;; MODIFIED: Check for nearby strategic locations
  let nearby-strategic-patches strategic-locations in-radius 15
  ifelse any? nearby-strategic-patches and random-float 1 < 0.7 [
    ;; If strategic locations are nearby, prioritize moving toward them
    let target min-one-of nearby-strategic-patches [distance myself]
    if target != nobody [
      face target
      fd 1.5 ;; Move faster toward strategic locations
    ]
  ][
    ifelse [terrain-type] of patch-here != "chinese-farm" [
      move-toward-chinese-farm
    ]
    [
      execute-action a
      if distance my-group-center > 5 [ setxy oldx oldy ]
    ]
  ]

  ask infantry with [team = "egyptian"] in-radius 5 [
    if random-float 1 < kill-prob [ die ]
  ]

  let s2 (list xcor ycor)
  let r compute-reward s s2

  ; MODIFIED: Bonus reward for capturing territory with higher values for strategic locations
  if [terrain-type] of patch-here = "chinese-farm" and [captured-by] of patch-here != "israeli" [
    ifelse [is-strategic] of patch-here [
      set r r + 1500 ;; Higher reward for strategic locations (slightly less than tanks)
      show (word "Israeli infantry " who " captured a strategic location!")
    ][
      set r r + 400 ;; Regular reward for normal locations
    ]
  ]

  update-q-table-israeli s a r s2
end

;------------------------------------------------
; Q-LEARNING FOR EGYPTIAN INFANTRY
;------------------------------------------------
to q-learn-move-egyptian-infantry
  ; Similar modifications as for tanks
  if action = "hold-position" [
    if [terrain-type] of patch-here != "chinese-farm" [
      move-toward-chinese-farm
      stop
    ]
    if (not is-list? defense-center) or (defense-center = 0) [
      set defense-center (list xcor ycor)
    ]

    ;; MODIFIED: Check for nearby strategic locations under Israeli control
    let strategic-israeli-captured strategic-locations with [captured-by = "israeli"] in-radius 15
    ifelse any? strategic-israeli-captured [
      show (word "Egyptian infantry " who " detected captured strategic location!")
      set action "surround"  ;; Change action mode to allow movement
    ][
      ifelse any? turtles with [ team = "israeli" ] in-radius 7 [  ; Increased from 5
        show (word "Egyptian infantry " who " detected an Israeli unit!")
        set action "surround"
      ] [
        ; Look for captured areas to reclaim - MODIFIED FOR BETTER MOVEMENT
        let israeli-captured-nearby patches in-radius 10 with [terrain-type = "chinese-farm" and captured-by = "israeli"]
        ifelse any? israeli-captured-nearby [
          show (word "Egyptian infantry " who " moving to recapture territory!")
          face min-one-of israeli-captured-nearby [distance myself]
          fd 1.25  ; Increased from 1

          ; Break out of hold position if we're trying to recapture
          if random-float 1 < 0.3 [  ; 30% chance to switch to active recapture
            set action "surround"
          ]
        ] [
          ; Random movement to avoid getting stuck
          rt (random 40 - 20)
          fd 0.75  ; Increased from 0.5
          if distancexy (item 0 defense-center) (item 1 defense-center) > 7 [
            face patch (item 0 defense-center) (item 1 defense-center)
            fd 1
          ]
        ]
        stop
      ]
    ]
  ]

  let s (list xcor ycor)
  let a choose-action-egyptian s
  let oldx xcor
  let oldy ycor

  ; Store original action value to restore it if we need to
  let original-action action

  ;; MODIFIED: Check for nearby strategic locations under Israeli control or not yet captured
  let strategic-targets strategic-locations with [captured-by = "israeli" or captured-by = "none"] in-radius 15
  ifelse any? strategic-targets and random-float 1 < 0.8 [
    ;; Prioritize recapturing strategic locations
    let target min-one-of strategic-targets [distance myself]
    if target != nobody [
      face target
      fd 1.75  ;; Move faster toward strategic locations
      show (word "Egyptian infantry " who " moving toward strategic location!")
    ]
  ][
    let nearby-israeli-tanks israeli-tanks in-radius 10  ; Increased radius
    let nearby-israeli-infantry infantry with [team = "israeli"] in-radius 12  ; Increased radius

    ; First priority: Engage enemy forces
    ifelse any? nearby-israeli-tanks or any? nearby-israeli-infantry [
      let nearest-enemy min-one-of (turtle-set nearby-israeli-tanks nearby-israeli-infantry) [ distance myself ]
      if nearest-enemy != nobody [
        set a "surround"
        face nearest-enemy
        fd 1.25  ; Increased speed
      ]
    ]
    [
      ; Second priority: Recapture territory - MODIFIED FOR BETTER MOVEMENT
      let israeli-captured patches in-radius 12 with [terrain-type = "chinese-farm" and captured-by = "israeli"]
      ifelse any? israeli-captured [
        face min-one-of israeli-captured [distance myself]
        fd 1.5  ; Increased from 1

        ; Claim territory we're standing on
        if [terrain-type] of patch-here = "chinese-farm" [
          ask patch-here [
            set captured-by "egyptian"
            set pcolor green
          ]
        ]
      ]
      [
        ; Third priority: Regular movement
        ifelse [terrain-type] of patch-here != "chinese-farm" [
          move-toward-chinese-farm
        ]
        [
          ; If we're in Chinese Farm and no enemies nearby, mix defend and exploration
          ifelse random-float 1 < 0.6 [  ; Reduced from 0.7
            execute-action "defend"
          ]
          [
            ; Increased chance of exploratory movement
            execute-action a

            ; Add some randomness to break out of stuck patterns
            if random-float 1 < 0.15 [  ; 15% chance for random movement
              rt (random 180 - 90)
              fd 1.5
            ]
          ]

          ; Relaxed group cohesion constraint - IMPORTANT FIX
          if distance my-group-center > 8 [  ; Increased from 5
            ; Don't teleport back anymore, just move toward group
            face my-group-center
            fd 1
          ]
        ]
      ]
    ]
  ]

  ; Restore original action if this was a hold-position unit, but with chance to break free
  if original-action = "hold-position" and random-float 1 < 0.85 [  ; 15% chance to escape hold position
    set action original-action
  ]

  let kills 0
  ask israeli-tanks in-radius 3 [  ; Increased range
    if random-float 1 < kill-prob [
      die
      set kills kills + 1
    ]
  ]
  ask infantry with [team = "israeli"] in-radius 3 [  ; Increased range
    if random-float 1 < kill-prob [
      die
      set kills kills + 1
    ]
  ]

  let s2 (list xcor ycor)
  let r compute-reward s s2

  ; MODIFIED: Extra reward for kills and recapturing territory with higher values for strategic locations
  set r (r + 50 * kills)
  if [terrain-type] of patch-here = "chinese-farm" and [captured-by] of patch-here = "israeli" [
    ifelse [is-strategic] of patch-here [
      set r r + 1500  ;; Higher reward for recapturing strategic locations
      show (word "Egyptian infantry " who " recaptured a strategic location!")
    ][
      set r r + 350  ;; Regular reward for normal locations
    ]
  ]

  update-q-table-egyptian s a r s2
end

;------------------------------------------------
; ACTION SELECTION & Q-VALUE LOOKUPS
;------------------------------------------------
to-report choose-action-israeli [s]
  if (random-float 1 < epsilon) [
    report one-of ["move-north" "move-south" "move-east" "move-west"]
  ]
  report max-arg s "israeli"
end

to-report choose-action-egyptian [s]
  if (random-float 1 < epsilon) [
    report one-of ["move-north" "move-south" "move-east" "move-west" "defend" "surround"]
  ]
  report max-arg s "egyptian"
end

to-report max-arg [s side]
  if side = "egyptian" [
    let actions ["move-north" "move-south" "move-east" "move-west" "defend" "surround"]
    let best-option first actions
    let best-value -99999
    foreach actions [ a ->
      let v (ifelse-value (side = "israeli")
                [ q-value-israeli s a ]
                [ q-value-egyptian s a ])
      if v > best-value [
        set best-option a
        set best-value v
      ]
    ]
    report best-option
  ]
  let actions ["move-north" "move-south" "move-east" "move-west"]
  let best-option first actions
  let best-value -99999
  foreach actions [ a ->
    let v q-value-israeli s a
    if v > best-value [
      set best-option a
      set best-value v
    ]
  ]
  report best-option
end

to-report q-value-israeli [s a]
  let entry filter [x -> (item 0 x = s and item 1 x = a)] q-table-israeli
  if empty? entry [ report 0 ]
  report last first entry
end

to-report q-value-egyptian [s a]
  let entry filter [x -> (item 0 x = s and item 1 x = a)] q-table-egyptian
  if empty? entry [ report 0 ]
  report last first entry
end

to-report update-q-entry [table s a q-value]
  let new-table filter [row -> not (item 0 row = s and item 1 row = a)] table
  report lput (list s a q-value) new-table
end

;------------------------------------------------
; MOVEMENT & REWARD
;------------------------------------------------
to execute-action [a]
  if a = "move-north" [ set heading 0   fd 1 ]
  if a = "move-south" [ set heading 180 fd 1 ]
  if a = "move-east"  [ set heading 90  fd 1 ]
  if a = "move-west"  [ set heading 270 fd 1 ]
  if a = "defend" [
    ; Modified to make units stay in place more
    let nearest-enemy min-one-of turtles with [team = "israeli"] [ distance myself ]
    if nearest-enemy != nobody [
      face nearest-enemy
      ; Only move forward if enemy is close
      if distance nearest-enemy < 3 [
        fd 1
      ]
    ]
  ]
  if a = "surround" [
  let target min-one-of turtles with [ team = "israeli" ] [ distance myself ]
  ifelse target != nobody [
  let direct-angle towards target
  let attack-range 2
  let current-distance distance target

  ; Modified to improve surrounding behavior
  ifelse current-distance <= attack-range [
    ; We're close enough to attack
    face target
    fd 1
    if random-float 1 < kill-prob [ ask target [ die ] ]
  ] [
    ; We're far, approach but try to flank
    ; Add some randomness to the approach angle for better surrounding
    set heading (towards target + (random 60 - 30))
    fd 1.5
  ]
] [
  ; No target found, look for Israeli-captured territory instead
  let israeli-captured patches in-radius 15 with [terrain-type = "chinese-farm" and captured-by = "israeli"]
  ifelse any? israeli-captured [
    face min-one-of israeli-captured [distance myself]
    fd 1.5
  ] [
    ; Just move randomly to avoid getting stuck
    rt random 90 - 45
    fd 1
  ]
]
  ]
end

to move-toward-chinese-farm
  let target chinese-farm-center
  let delta-x [pxcor] of target - xcor
  let delta-y [pycor] of target - ycor
  ifelse abs delta-x > abs delta-y [
    if delta-x > 0 [ set heading 90  fd 1 ]
    if delta-x < 0 [ set heading 270 fd 1 ]
  ]
  [
    if delta-y > 0 [ set heading 0   fd 1 ]
    if delta-y < 0 [ set heading 180 fd 1 ]
  ]
end

to-report compute-reward [s s2]
  let oldx item 0 s
  let newx item 0 s2
  let oldy item 1 s
  let newy item 1 s2

  ; Base reward calculation
  let r 0

  ; Distance-based reward components
  let old-dist 0
  let new-dist 0

  if team = "israeli" [
    ; Israeli reward is based on moving toward/into the Chinese Farm and enemy units
    ; Distance to farm center
    set old-dist distance chinese-farm-center
    set new-dist sqrt ((newx - [pxcor] of chinese-farm-center) ^ 2 + (newy - [pycor] of chinese-farm-center) ^ 2)

    ; Reward for moving closer to the farm
    if new-dist < old-dist [
      set r r + 10
    ]

    ; Reward for being in the farm
    if [terrain-type] of patch newx newy = "chinese-farm" [
      set r r + 50

      ; ENHANCED: Extra reward for being in strategic locations
      if [is-strategic] of patch newx newy [
        set r r + (100 * [strategic-value] of patch newx newy)
        ; Show message about strategic positioning
        if [captured-by] of patch newx newy != "israeli" [
          show (word "Israeli unit " who " positioning to capture a strategic location!")
        ]
      ]
    ]

    ; Reward for eliminating enemy units
    let nearby-enemies count turtles with [team = "egyptian"] in-radius 3
    set r r + (nearby-enemies * 20)

    ; Strategic objective reward - control of Chinese Farm
    let israeli-control count chinese-farm-patches with [captured-by = "israeli"]
    let control-pct (israeli-control / count chinese-farm-patches) * 100
    set r r + (control-pct / 10)  ; Small incremental reward based on control percentage
  ]

  if team = "egyptian" [
    ; Egyptian reward is defensive - hold the farm and eliminate invaders
    if [terrain-type] of patch newx newy = "chinese-farm" [
      set r r + 30

      ; ENHANCED: Extra reward for being in strategic locations
      if [is-strategic] of patch newx newy [
        set r r + (75 * [strategic-value] of patch newx newy)
        ; Show message about strategic positioning
        if [captured-by] of patch newx newy != "egyptian" [
          show (word "Egyptian unit " who " positioning to defend a strategic location!")
        ]
      ]
    ]

    ; Reward for eliminating enemy units
    let nearby-enemies count turtles with [team = "israeli"] in-radius 3
    set r r + (nearby-enemies * 25)

    ; Strategic objective reward - control of Chinese Farm
    let egyptian-control count chinese-farm-patches with [captured-by = "egyptian"]
    let control-pct (egyptian-control / count chinese-farm-patches) * 100
    set r r + (control-pct / 5)  ; More significant for defenders
  ]

  report r
end

to update-q-table-israeli [s a r s2]
  let next-action max-arg s2 "israeli"
  let old-q q-value-israeli s a
  let next-q q-value-israeli s2 next-action

  let new-q (old-q + alpha * (r + gamma * next-q - old-q))

  ; Bonus Q-values for strategic actions
  if [is-strategic] of patch-here [
    set new-q new-q * 1.25  ; 25% boost for strategic importance
  ]

  set q-table-israeli update-q-entry q-table-israeli s a new-q
end

to update-q-table-egyptian [s a r s2]
  let next-action max-arg s2 "egyptian"
  let old-q q-value-egyptian s a
  let next-q q-value-egyptian s2 next-action

  let new-q (old-q + alpha * (r + gamma * next-q - old-q))

  ; Bonus Q-values for strategic actions
  if [is-strategic] of patch-here [
    set new-q new-q * 1.3  ; 30% boost for strategic importance - Egyptians value strategic points more
  ]

  set q-table-egyptian update-q-entry q-table-egyptian s a new-q
end

; Enhanced capture function that considers strategic locations
to capture-chinese-farm
  ask turtles [
    if team = "israeli" [
      ask patch-here [
        if terrain-type = "chinese-farm" and captured-by != "israeli" [
          ; Check if this is a strategic location
          ifelse is-strategic [
            set captured-by "israeli"
            set pcolor orange  ; Different color for strategic locations under Israeli control
            ; Report strategic capture
            show (word "Strategic location captured by Israeli forces!")
            ; Reset control time
            set control-time 0
          ] [
            set captured-by "israeli"
            set pcolor brown
          ]
        ]
      ]
    ]
    if team = "egyptian" [
      ask patch-here [
        if terrain-type = "chinese-farm" [
          ; Check if this is a strategic location
          ifelse is-strategic [
            set captured-by "egyptian"
            set pcolor turquoise  ; Different color for strategic locations under Egyptian control
            ; Report strategic capture
            show (word "Strategic location secured by Egyptian forces!")
            ; Reset control time
            set control-time 0
          ] [
            set captured-by "egyptian"
            set pcolor green
          ]
        ]
      ]
    ]
  ]

  ; Track control time for strategic locations
  ask patches with [is-strategic] [
    if captured-by != "none" [
      set control-time control-time + 1

      ; Increase defensive bonus the longer a location is held
      if control-time mod 10 = 0 and control-time <= 50 [  ; Cap at 50 ticks
        set defensive-bonus defensive-bonus + 0.02
        if defensive-bonus > 0.5 [set defensive-bonus 0.5]  ; Cap at 50%
      ]
    ]
  ]

  ; Visual indicator of control percentages
  let total-chinese-farm count chinese-farm-patches
  let egyptian-control count chinese-farm-patches with [captured-by = "egyptian"]
  let israeli-control count chinese-farm-patches with [captured-by = "israeli"]
  let egyptian-percent (egyptian-control / total-chinese-farm) * 100
  let israeli-percent (israeli-control / total-chinese-farm) * 100

  ; Strategic control indicators
  let strategic-total count patches with [is-strategic]
  let strategic-egyptian count patches with [is-strategic and captured-by = "egyptian"]
  let strategic-israeli count patches with [is-strategic and captured-by = "israeli"]

  show (word "Control: Egyptian " precision egyptian-percent 1 "%, Israeli " precision israeli-percent 1 "%")
  show (word "Strategic Control: Egyptian " strategic-egyptian "/" strategic-total
       ", Israeli " strategic-israeli "/" strategic-total)
end

; Enhanced to prioritize strategic locations
to reinforce-chinese-farm
  ; Track all strategic locations
  let strategic-patches patches with [is-strategic]
  let israeli-strategic strategic-patches with [captured-by = "israeli"]
  let egyptian-strategic strategic-patches with [captured-by = "egyptian"]
  let neutral-strategic strategic-patches with [captured-by = "none"]

  ; Egyptian tanks prioritize recapturing strategic positions
  ask egyptian-tanks [
    ; If there are Israeli-controlled strategic locations, prioritize them
    ifelse any? israeli-strategic in-radius 20 [
      let target min-one-of israeli-strategic [distance myself]
      if target != nobody [
        face target
        fd 2  ; Move quickly toward strategic targets
        show (word "Egyptian tank " who " moving to recapture strategic location!")
      ]
    ][
      ; Otherwise use the standard reinforcement logic
      ifelse any? turtles with [team = "israeli"] in-radius 5 [
        let target min-one-of turtles with [team = "israeli"] [distance myself]
        if target != nobody [
          face target
          fd 1
        ]
      ][
        ; Look for any Israeli-captured areas
        let israeli-patches patches in-radius 15 with [terrain-type = "chinese-farm" and captured-by = "israeli"]
        ifelse any? israeli-patches [
          face min-one-of israeli-patches [distance myself]
          fd 1.5
        ][
          ; Random movement to avoid getting stuck
          if random-float 1 < 0.2 [
            rt random 90 - 45
            fd 1
          ]
        ]
      ]
    ]
  ]

  ; Egyptian infantry also prioritize strategic locations
  ask infantry with [team = "egyptian"] [
    ; If there are Israeli-controlled strategic locations, prioritize them
    ifelse any? israeli-strategic in-radius 15 [
      let target min-one-of israeli-strategic [distance myself]
      if target != nobody [
        face target
        fd 1.5
        show (word "Egyptian infantry " who " moving to recapture strategic location!")
      ]
    ][
      ; Otherwise use the standard reinforcement logic
      ifelse any? turtles with [team = "israeli"] in-radius 5 [
        let target min-one-of turtles with [team = "israeli"] [distance myself]
        if target != nobody [
          face target
          fd 1
        ]
      ][
        ; Look for any Israeli-captured areas
        let israeli-patches patches in-radius 10 with [terrain-type = "chinese-farm" and captured-by = "israeli"]
        ifelse any? israeli-patches [
          face min-one-of israeli-patches [distance myself]
          fd 1.25
        ][
          ; Random movement to avoid getting stuck
          if random-float 1 < 0.2 [
            rt random 90 - 45
            fd 1
          ]
        ]
      ]
    ]
  ]

  ; Israeli forces also prioritize strategic locations
  ask turtles with [team = "israeli"] [
    ; If there are neutral or Egyptian-controlled strategic locations, prioritize them
    let target-strategic (patch-set neutral-strategic egyptian-strategic)
    if any? target-strategic in-radius 20 [
      let target min-one-of target-strategic [distance myself]
      if target != nobody and random-float 1 < 0.7 [  ; 70% chance to prioritize strategic locations
        face target
        fd 1.75
        show (word "Israeli unit " who " moving to capture strategic location!")
      ]
    ]
  ]
end

; Enhanced shooting function that considers strategic location defensive bonuses
to check-shooting
  ask infantry [
    let targets infantry in-radius 3 with [team != [team] of myself]
    if any? targets [
      show (word "Infantry " who " is shooting enemy infantry!")
    ]
    ask targets [
      ; Adjust kill probability based on defensive bonus if target is on strategic location
      let effective-kill-prob kill-prob
      if [is-strategic] of patch-here and [captured-by] of patch-here = team [
        set effective-kill-prob kill-prob * (1 - [defensive-bonus] of patch-here)
        if effective-kill-prob < 0.1 [set effective-kill-prob 0.1]  ; Minimum 10% chance
      ]
      if random-float 1 < effective-kill-prob [die]
    ]
  ]

  ask israeli-tanks [
    let targets turtles in-radius 5 with [team = "egyptian"]
    if any? targets [
      show (word "Israeli tank " who " is shooting Egyptian units!")
    ]
    ask targets [
      ; Adjust kill probability based on defensive bonus if target is on strategic location
      let effective-kill-prob kill-prob
      if [is-strategic] of patch-here and [captured-by] of patch-here = team [
        set effective-kill-prob kill-prob * (1 - [defensive-bonus] of patch-here)
        if effective-kill-prob < 0.1 [set effective-kill-prob 0.1]  ; Minimum 10% chance
      ]
      if random-float 1 < effective-kill-prob [die]
    ]
  ]

  ask egyptian-tanks [
    let targets turtles in-radius 5 with [team = "israeli"]
    if any? targets [
      show (word "Egyptian tank " who " is shooting Israeli units!")
    ]
    ask targets [
      ; Adjust kill probability based on defensive bonus if target is on strategic location
      let effective-kill-prob kill-prob
      if [is-strategic] of patch-here and [captured-by] of patch-here = team [
        set effective-kill-prob kill-prob * (1 - [defensive-bonus] of patch-here)
        if effective-kill-prob < 0.1 [set effective-kill-prob 0.1]  ; Minimum 10% chance
      ]
      if random-float 1 < effective-kill-prob [die]
    ]
  ]
end

; Enhanced win condition that gives more weight to strategic locations
to check-win-condition
  ; Count troops on each side
  let israeli-count count turtles with [team = "israeli"]
  let egyptian-count count turtles with [team = "egyptian"]

  ; Check if either side has fewer than 10 troops
  if israeli-count < 10 or egyptian-count < 10 [
    ; Count captured territory
    let total-chinese-farm count chinese-farm-patches
    let egyptian-control count chinese-farm-patches with [captured-by = "egyptian"]
    let israeli-control count chinese-farm-patches with [captured-by = "israeli"]

    ; Strategic location control (weighted more heavily)
    let strategic-total count patches with [is-strategic]
    let strategic-egyptian count patches with [is-strategic and captured-by = "egyptian"]
    let strategic-israeli count patches with [is-strategic and captured-by = "israeli"]

    ; Calculate weighted territory control (strategic locations count double)
    let strategic-weight 3  ; Strategic locations are worth 3x normal patches
    let weighted-egyptian (egyptian-control - strategic-egyptian) + (strategic-egyptian * strategic-weight)
    let weighted-israeli (israeli-control - strategic-israeli) + (strategic-israeli * strategic-weight)
    let weighted-total (total-chinese-farm - strategic-total) + (strategic-total * strategic-weight)

    ; Calculate percentages
    let egyptian-percent (weighted-egyptian / weighted-total) * 100
    let israeli-percent (weighted-israeli / weighted-total) * 100

    ; Determine the winner based on territory
    ifelse israeli-percent > egyptian-percent [
      show "ISRAELI VICTORY!"
      show (word "Final control: Israeli " precision israeli-percent 1 "%, Egyptian " precision egyptian-percent 1 "%")
      show (word "Strategic locations: Israeli " strategic-israeli "/" strategic-total ", Egyptian " strategic-egyptian "/" strategic-total)
      show (word "Final troop count: Israeli " israeli-count ", Egyptian " egyptian-count)
    ] [
      ifelse egyptian-percent > israeli-percent [
        show "EGYPTIAN VICTORY!"
        show (word "Final control: Egyptian " precision egyptian-percent 1 "%, Israeli " precision israeli-percent 1 "%")
        show (word "Strategic locations: Egyptian " strategic-egyptian "/" strategic-total ", Israeli " strategic-israeli "/" strategic-total)
        show (word "Final troop count: Egyptian " egyptian-count ", Israeli " israeli-count)
      ] [
        show "DRAW - EQUAL TERRITORIAL CONTROL"
        show (word "Final control: Both sides " precision israeli-percent 1 "%")
        show (word "Strategic locations: Israeli " strategic-israeli "/" strategic-total ", Egyptian " strategic-egyptian "/" strategic-total)
        show (word "Final troop count: Israeli " israeli-count ", Egyptian " egyptian-count)
      ]
    ]

    ; Show message and stop the simulation
    user-message (word "Simulation ended. "
                  ifelse-value (israeli-percent > egyptian-percent) ["Israeli victory!"]
                  [ifelse-value (egyptian-percent > israeli-percent) ["Egyptian victory!"] ["Draw!"]])
    stop
  ]
end

; NEW: Add a function to initialize the strategic values and defensive bonuses
to setup-patch-properties
  ; Need to be called after setup-strategic-locations in the setup procedure

  ; Initialize strategic values for existing strategic locations
  ask patches with [is-strategic] [
    ; If not already set, give default values
    if strategic-value = 0 [set strategic-value 5]  ; Default medium value
    if defensive-bonus = 0 [set defensive-bonus 0.2]  ; Default small bonus

    ; Initialize control time
    set control-time 0
  ]
end

to-report my-group-center
  let mates turtles with [group-id = [group-id] of myself]
  if any? mates [
    let avg-x mean [xcor] of mates
    let avg-y mean [ycor] of mates
    report patch avg-x avg-y
  ]
  report patch-here
end
@#$#@#$#@
GRAPHICS-WINDOW
210
10
718
519
-1
-1
5.0
1
10
1
1
1
0
1
1
1
0
99
0
99
1
1
1
ticks
30.0

BUTTON
40
73
106
106
NIL
Setup
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

BUTTON
65
160
128
193
NIL
Go
T
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

PLOT
855
188
1055
338
Israeli vs Egyptian
NIL
NIL
0.0
10.0
0.0
10.0
true
false
"" ""
PENS
"default" 1.0 0 -15637942 true "" "plot count turtles with [team = \"israeli\"]"
"pen-1" 1.0 0 -5825686 true "" "plot count turtles with [team = \"egyptian\"]"

@#$#@#$#@
## WHAT IS IT?

(a general understanding of what the model is trying to show or explain)

## HOW IT WORKS

(what rules the agents use to create the overall behavior of the model)

## HOW TO USE IT

(how to use the model, including a description of each of the items in the Interface tab)

## THINGS TO NOTICE

(suggested things for the user to notice while running the model)

## THINGS TO TRY

(suggested things for the user to try to do (move sliders, switches, etc.) with the model)

## EXTENDING THE MODEL

(suggested things to add or change in the Code tab to make the model more complicated, detailed, accurate, etc.)

## NETLOGO FEATURES

(interesting or unusual features of NetLogo that the model uses, particularly in the Code tab; or where workarounds were needed for missing features)

## RELATED MODELS

(models in the NetLogo Models Library and elsewhere which are of related interest)

## CREDITS AND REFERENCES

(a reference to the model's URL on the web if it has one, as well as any other necessary credits, citations, and links)
@#$#@#$#@
default
true
0
Polygon -7500403 true true 150 5 40 250 150 205 260 250

airplane
true
0
Polygon -7500403 true true 150 0 135 15 120 60 120 105 15 165 15 195 120 180 135 240 105 270 120 285 150 270 180 285 210 270 165 240 180 180 285 195 285 165 180 105 180 60 165 15

arrow
true
0
Polygon -7500403 true true 150 0 0 150 105 150 105 293 195 293 195 150 300 150

box
false
0
Polygon -7500403 true true 150 285 285 225 285 75 150 135
Polygon -7500403 true true 150 135 15 75 150 15 285 75
Polygon -7500403 true true 15 75 15 225 150 285 150 135
Line -16777216 false 150 285 150 135
Line -16777216 false 150 135 15 75
Line -16777216 false 150 135 285 75

bug
true
0
Circle -7500403 true true 96 182 108
Circle -7500403 true true 110 127 80
Circle -7500403 true true 110 75 80
Line -7500403 true 150 100 80 30
Line -7500403 true 150 100 220 30

butterfly
true
0
Polygon -7500403 true true 150 165 209 199 225 225 225 255 195 270 165 255 150 240
Polygon -7500403 true true 150 165 89 198 75 225 75 255 105 270 135 255 150 240
Polygon -7500403 true true 139 148 100 105 55 90 25 90 10 105 10 135 25 180 40 195 85 194 139 163
Polygon -7500403 true true 162 150 200 105 245 90 275 90 290 105 290 135 275 180 260 195 215 195 162 165
Polygon -16777216 true false 150 255 135 225 120 150 135 120 150 105 165 120 180 150 165 225
Circle -16777216 true false 135 90 30
Line -16777216 false 150 105 195 60
Line -16777216 false 150 105 105 60

car
false
0
Polygon -7500403 true true 300 180 279 164 261 144 240 135 226 132 213 106 203 84 185 63 159 50 135 50 75 60 0 150 0 165 0 225 300 225 300 180
Circle -16777216 true false 180 180 90
Circle -16777216 true false 30 180 90
Polygon -16777216 true false 162 80 132 78 134 135 209 135 194 105 189 96 180 89
Circle -7500403 true true 47 195 58
Circle -7500403 true true 195 195 58

circle
false
0
Circle -7500403 true true 0 0 300

circle 2
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240

cow
false
0
Polygon -7500403 true true 200 193 197 249 179 249 177 196 166 187 140 189 93 191 78 179 72 211 49 209 48 181 37 149 25 120 25 89 45 72 103 84 179 75 198 76 252 64 272 81 293 103 285 121 255 121 242 118 224 167
Polygon -7500403 true true 73 210 86 251 62 249 48 208
Polygon -7500403 true true 25 114 16 195 9 204 23 213 25 200 39 123

cylinder
false
0
Circle -7500403 true true 0 0 300

dot
false
0
Circle -7500403 true true 90 90 120

face happy
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 255 90 239 62 213 47 191 67 179 90 203 109 218 150 225 192 218 210 203 227 181 251 194 236 217 212 240

face neutral
false
0
Circle -7500403 true true 8 7 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Rectangle -16777216 true false 60 195 240 225

face sad
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 168 90 184 62 210 47 232 67 244 90 220 109 205 150 198 192 205 210 220 227 242 251 229 236 206 212 183

fish
false
0
Polygon -1 true false 44 131 21 87 15 86 0 120 15 150 0 180 13 214 20 212 45 166
Polygon -1 true false 135 195 119 235 95 218 76 210 46 204 60 165
Polygon -1 true false 75 45 83 77 71 103 86 114 166 78 135 60
Polygon -7500403 true true 30 136 151 77 226 81 280 119 292 146 292 160 287 170 270 195 195 210 151 212 30 166
Circle -16777216 true false 215 106 30

flag
false
0
Rectangle -7500403 true true 60 15 75 300
Polygon -7500403 true true 90 150 270 90 90 30
Line -7500403 true 75 135 90 135
Line -7500403 true 75 45 90 45

flower
false
0
Polygon -10899396 true false 135 120 165 165 180 210 180 240 150 300 165 300 195 240 195 195 165 135
Circle -7500403 true true 85 132 38
Circle -7500403 true true 130 147 38
Circle -7500403 true true 192 85 38
Circle -7500403 true true 85 40 38
Circle -7500403 true true 177 40 38
Circle -7500403 true true 177 132 38
Circle -7500403 true true 70 85 38
Circle -7500403 true true 130 25 38
Circle -7500403 true true 96 51 108
Circle -16777216 true false 113 68 74
Polygon -10899396 true false 189 233 219 188 249 173 279 188 234 218
Polygon -10899396 true false 180 255 150 210 105 210 75 240 135 240

house
false
0
Rectangle -7500403 true true 45 120 255 285
Rectangle -16777216 true false 120 210 180 285
Polygon -7500403 true true 15 120 150 15 285 120
Line -16777216 false 30 120 270 120

leaf
false
0
Polygon -7500403 true true 150 210 135 195 120 210 60 210 30 195 60 180 60 165 15 135 30 120 15 105 40 104 45 90 60 90 90 105 105 120 120 120 105 60 120 60 135 30 150 15 165 30 180 60 195 60 180 120 195 120 210 105 240 90 255 90 263 104 285 105 270 120 285 135 240 165 240 180 270 195 240 210 180 210 165 195
Polygon -7500403 true true 135 195 135 240 120 255 105 255 105 285 135 285 165 240 165 195

line
true
0
Line -7500403 true 150 0 150 300

line half
true
0
Line -7500403 true 150 0 150 150

pentagon
false
0
Polygon -7500403 true true 150 15 15 120 60 285 240 285 285 120

person
false
0
Circle -7500403 true true 110 5 80
Polygon -7500403 true true 105 90 120 195 90 285 105 300 135 300 150 225 165 300 195 300 210 285 180 195 195 90
Rectangle -7500403 true true 127 79 172 94
Polygon -7500403 true true 195 90 240 150 225 180 165 105
Polygon -7500403 true true 105 90 60 150 75 180 135 105

plant
false
0
Rectangle -7500403 true true 135 90 165 300
Polygon -7500403 true true 135 255 90 210 45 195 75 255 135 285
Polygon -7500403 true true 165 255 210 210 255 195 225 255 165 285
Polygon -7500403 true true 135 180 90 135 45 120 75 180 135 210
Polygon -7500403 true true 165 180 165 210 225 180 255 120 210 135
Polygon -7500403 true true 135 105 90 60 45 45 75 105 135 135
Polygon -7500403 true true 165 105 165 135 225 105 255 45 210 60
Polygon -7500403 true true 135 90 120 45 150 15 180 45 165 90

sheep
false
15
Circle -1 true true 203 65 88
Circle -1 true true 70 65 162
Circle -1 true true 150 105 120
Polygon -7500403 true false 218 120 240 165 255 165 278 120
Circle -7500403 true false 214 72 67
Rectangle -1 true true 164 223 179 298
Polygon -1 true true 45 285 30 285 30 240 15 195 45 210
Circle -1 true true 3 83 150
Rectangle -1 true true 65 221 80 296
Polygon -1 true true 195 285 210 285 210 240 240 210 195 210
Polygon -7500403 true false 276 85 285 105 302 99 294 83
Polygon -7500403 true false 219 85 210 105 193 99 201 83

square
false
0
Rectangle -7500403 true true 30 30 270 270

square 2
false
0
Rectangle -7500403 true true 30 30 270 270
Rectangle -16777216 true false 60 60 240 240

star
false
0
Polygon -7500403 true true 151 1 185 108 298 108 207 175 242 282 151 216 59 282 94 175 3 108 116 108

target
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240
Circle -7500403 true true 60 60 180
Circle -16777216 true false 90 90 120
Circle -7500403 true true 120 120 60

tree
false
0
Circle -7500403 true true 118 3 94
Rectangle -6459832 true false 120 195 180 300
Circle -7500403 true true 65 21 108
Circle -7500403 true true 116 41 127
Circle -7500403 true true 45 90 120
Circle -7500403 true true 104 74 152

triangle
false
0
Polygon -7500403 true true 150 30 15 255 285 255

triangle 2
false
0
Polygon -7500403 true true 150 30 15 255 285 255
Polygon -16777216 true false 151 99 225 223 75 224

truck
false
0
Rectangle -7500403 true true 4 45 195 187
Polygon -7500403 true true 296 193 296 150 259 134 244 104 208 104 207 194
Rectangle -1 true false 195 60 195 105
Polygon -16777216 true false 238 112 252 141 219 141 218 112
Circle -16777216 true false 234 174 42
Rectangle -7500403 true true 181 185 214 194
Circle -16777216 true false 144 174 42
Circle -16777216 true false 24 174 42
Circle -7500403 false true 24 174 42
Circle -7500403 false true 144 174 42
Circle -7500403 false true 234 174 42

turtle
true
0
Polygon -10899396 true false 215 204 240 233 246 254 228 266 215 252 193 210
Polygon -10899396 true false 195 90 225 75 245 75 260 89 269 108 261 124 240 105 225 105 210 105
Polygon -10899396 true false 105 90 75 75 55 75 40 89 31 108 39 124 60 105 75 105 90 105
Polygon -10899396 true false 132 85 134 64 107 51 108 17 150 2 192 18 192 52 169 65 172 87
Polygon -10899396 true false 85 204 60 233 54 254 72 266 85 252 107 210
Polygon -7500403 true true 119 75 179 75 209 101 224 135 220 225 175 261 128 261 81 224 74 135 88 99

wheel
false
0
Circle -7500403 true true 3 3 294
Circle -16777216 true false 30 30 240
Line -7500403 true 150 285 150 15
Line -7500403 true 15 150 285 150
Circle -7500403 true true 120 120 60
Line -7500403 true 216 40 79 269
Line -7500403 true 40 84 269 221
Line -7500403 true 40 216 269 79
Line -7500403 true 84 40 221 269

wolf
false
0
Polygon -16777216 true false 253 133 245 131 245 133
Polygon -7500403 true true 2 194 13 197 30 191 38 193 38 205 20 226 20 257 27 265 38 266 40 260 31 253 31 230 60 206 68 198 75 209 66 228 65 243 82 261 84 268 100 267 103 261 77 239 79 231 100 207 98 196 119 201 143 202 160 195 166 210 172 213 173 238 167 251 160 248 154 265 169 264 178 247 186 240 198 260 200 271 217 271 219 262 207 258 195 230 192 198 210 184 227 164 242 144 259 145 284 151 277 141 293 140 299 134 297 127 273 119 270 105
Polygon -7500403 true true -1 195 14 180 36 166 40 153 53 140 82 131 134 133 159 126 188 115 227 108 236 102 238 98 268 86 269 92 281 87 269 103 269 113

x
false
0
Polygon -7500403 true true 270 75 225 30 30 225 75 270
Polygon -7500403 true true 30 75 75 30 270 225 225 270
@#$#@#$#@
NetLogo 6.4.0
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
default
0.0
-0.2 0 0.0 1.0
0.0 1 1.0 0.0
0.2 0 0.0 1.0
link direction
true
0
Line -7500403 true 150 150 90 180
Line -7500403 true 150 150 210 180
@#$#@#$#@
0
@#$#@#$#@
