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

  ;; X-position of the canal's center columns
  canal-x

  ;; Group IDs to keep track of which turtles spawn together
  group-counter

  ;; Patches that define the "Chinese Farm" area
  chinese-farm-patches
  chinese-farm-center
]

breed [israeli-tanks israeli-tank]
breed [egyptian-tanks egyptian-tank]
breed [infantry soldier]

patches-own [
  terrain-type
  captured-by  ;; "israeli", "egyptian", or "none"
]
turtles-own [
  state
  action
  team
  group-id
  canal-wait
  has-crossed-canal
  canal-timer  ;; Add this line to track time on the canal
]

to setup
  clear-all
  set battlefield-width 100
  set battlefield-height 100
  resize-world 0 (battlefield-width - 1) 0 (battlefield-height - 1)
  set-patch-size 5
  set canal-x floor (battlefield-width / 2)
  set alpha 0.1
  set gamma 0.9
  set epsilon 0.5
  set q-table-israeli []
  set q-table-egyptian []
  set group-counter 0
  set chinese-farm-patches []
  setup-terrain
  setup-units
  reset-ticks
  ;; Initialize the canal-timer to 0 for all turtles
  ask turtles [ set canal-timer 0 ]
  ;; Make sure all turtles have 'has-crossed-canal' set to FALSE
  ask turtles [ set has-crossed-canal false ]
end

to setup-terrain
  ask patches [
    ;; Canal spans x = canal-x-1, canal-x, canal-x+1
    if (pxcor = canal-x - 1) or (pxcor = canal-x) or (pxcor = canal-x + 1) [
      set terrain-type "water"
      set pcolor blue
    ]
    if pxcor <= canal-x - 2 [
      set terrain-type "desert-west"
      set pcolor brown
    ]
    if pxcor >= canal-x + 2 [
      set terrain-type "desert-east"
      set pcolor yellow
    ]
  ]

  ;; "Chinese Farm" region on the west side
  ask patches with [pxcor >= 5 and pxcor <= 30 and pycor >= 10 and pycor <= 40] [
    set terrain-type "chinese-farm"
    set pcolor green
    set captured-by "none"  ;; Initialize to "none" for Chinese Farm patches
  ]
  set chinese-farm-patches patches with [terrain-type = "chinese-farm"]

  ;; Define the center patch of the Chinese Farm
  let center-x 17
  let center-y 24
  set chinese-farm-center patch center-x center-y
end

to setup-units
  ;; Israeli Tanks: 5 groups of 5 each => 25 tanks
  repeat 5 [
    let cluster-x (canal-x + 5 + random 3)
    let cluster-y (10 + random 5)

    create-israeli-tanks 5 [
      set group-id group-counter
      set team "israeli"
      set canal-wait -1
      set shape "circle"
      set color 135   ;; pink for Israeli tanks
      setxy (cluster-x + random 2) (cluster-y + random 2)

      set state (list xcor ycor)
      set action ""
    ]
    set group-counter group-counter + 1
  ]

  ;; Egyptian Tanks: 5 groups of 5 each => 25 tanks
  repeat 5 [
    let cluster-x (5 + random 3)
    let cluster-y (10 + random 5)

    create-egyptian-tanks 5 [
      set group-id group-counter
      set team "egyptian"
      set canal-wait -1
      set shape "circle"
      set color 25    ;; orange for Egyptian tanks
      setxy (cluster-x + random 2) (cluster-y + random 2)

      set state (list xcor ycor)
      set action ""
    ]
    set group-counter group-counter + 1
  ]

  ;; Israeli Infantry: 5 groups of 5 each => 25 infantry
  repeat 5 [
    let cluster-x (canal-x + 2 + random 5)
    let cluster-y (random 10)

    create-infantry 5 [
      set group-id group-counter
      set team "israeli"
      set canal-wait -1
      set shape "person"
      set color 105   ;; blue for Israeli infantry
      setxy (cluster-x + random 2) (cluster-y + random 2)

      set state (list xcor ycor)
      set action ""
    ]
    set group-counter group-counter + 1
  ]

  ;; Egyptian Infantry: 5 groups of 5 each => 25 infantry
  repeat 5 [
    let cluster-x (random 10)
    let cluster-y (20 + random 10)

    create-infantry 5 [
      set group-id group-counter
      set team "egyptian"
      set canal-wait -1
      set shape "person"
      set color 15    ;; red for Egyptian infantry
      setxy (cluster-x + random 2) (cluster-y + random 2)

      set state (list xcor ycor)
      set action ""
    ]
    set group-counter group-counter + 1
  ]
end

;; =========================================
;; MAIN LOOP
;; =========================================
to go
  ask israeli-tanks [ q-learn-move-israeli ]
  ask egyptian-tanks [ q-learn-move-egyptian ]

  ask infantry with [team = "israeli"] [ q-learn-move-israeli-infantry ]
  ask infantry with [team = "egyptian"] [ q-learn-move-egyptian-infantry ]

  check-shooting
  capture-chinese-farm  ;; Capture patches within the Chinese Farm

  ;; Display counts every tick
  ;show (word "Israeli Units: " count turtles with [team = "israeli"])
  ;show (word "Egyptian Units: " count turtles with [team = "egyptian"])

  tick
end

;; =========================================
;; Q-LEARNING FOR ISRAELI TANKS
;; =========================================

to q-learn-move-israeli
  let s (list xcor ycor)
  let a choose-action-israeli s

  let oldx xcor
  let oldy ycor

  ;; If the unit is not in the Chinese Farm, use hardcoded movement
  ifelse [terrain-type] of patch-here != "chinese-farm" [
    move-toward-chinese-farm
  ]
  [
    ;; If the unit is in the Chinese Farm, use Q-learning
    handle-canal-wait

    ifelse (canal-wait > 0)
    [
      set canal-wait canal-wait - 1
    ]
    [
      execute-action a

      ;; Group cohesion logic
      if distance my-group-center > 5 [
        setxy oldx oldy
      ]
    ]
  ]

  ;; Handle nearby enemy destruction
  ask egyptian-tanks in-radius 2 [ die ]
  ask infantry with [team = "egyptian"] in-radius 2 [ die ]

  let s2 (list xcor ycor)
  let r compute-reward s s2

  update-q-table-israeli s a r s2
end

;; =========================================
;; Q-LEARNING FOR EGYPTIAN TANKS
;; (Kill reward: +50 per Israeli killed)
;; =========================================

to q-learn-move-egyptian
  let s (list xcor ycor)
  let a choose-action-egyptian s

  let oldx xcor
  let oldy ycor

  ;; If the unit is not in the Chinese Farm, use hardcoded movement
  ifelse [terrain-type] of patch-here != "chinese-farm" [
    move-toward-chinese-farm
  ]
  [
    ;; If the unit is in the Chinese Farm, use Q-learning
    execute-action a

    ;; Group cohesion logic
    if distance my-group-center > 5 [
      setxy oldx oldy
    ]
  ]

  let kills 0
  ask israeli-tanks in-radius 2 [
    die
    set kills kills + 1
  ]
  ask infantry with [team = "israeli"] in-radius 2 [
    die
    set kills kills + 1
  ]

  let s2 (list xcor ycor)
  let r compute-reward s s2
  set r (r + 50 * kills)  ;; +50 per Israeli kill

  update-q-table-egyptian s a r s2
end

;; =========================================
;; Q-LEARNING FOR ISRAELI INFANTRY
;; =========================================

to q-learn-move-israeli-infantry
  let s (list xcor ycor)
  let a choose-action-israeli s

  let oldx xcor
  let oldy ycor

  ;; If the unit is not in the Chinese Farm, use hardcoded movement
  ifelse [terrain-type] of patch-here != "chinese-farm" [
    move-toward-chinese-farm
  ]
  [
    ;; If the unit is in the Chinese Farm, use Q-learning
    handle-canal-wait

    ifelse (canal-wait > 0)
    [
      set canal-wait canal-wait - 1
    ]
    [
      execute-action a

      ;; Group cohesion logic
      if distance my-group-center > 5 [
        setxy oldx oldy
      ]
    ]
  ]

  ;; Possibly kill adjacent Egyptian infantry (no kill reward)
  ask infantry with [team = "egyptian"] in-radius 2 [ die ]

  let s2 (list xcor ycor)
  let r compute-reward s s2

  update-q-table-israeli s a r s2
end

;; =========================================
;; Q-LEARNING FOR EGYPTIAN INFANTRY
;; (Kill reward: +50 per Israeli killed)
;; =========================================

to q-learn-move-egyptian-infantry
  let s (list xcor ycor)
  let a choose-action-egyptian s

  let oldx xcor
  let oldy ycor

  ;; If the unit is not in the Chinese Farm, use hardcoded movement
  ifelse [terrain-type] of patch-here != "chinese-farm" [
    move-toward-chinese-farm
  ]
  [
    ;; If the unit is in the Chinese Farm, use Q-learning
    execute-action a

    ;; Group cohesion logic
    if distance my-group-center > 5 [
      setxy oldx oldy
    ]
  ]

  let kills 0
  ask infantry with [team = "israeli"] in-radius 2 [
    die
    set kills kills + 1
  ]
  ask israeli-tanks in-radius 2 [
    die
    set kills kills + 1
  ]

  let s2 (list xcor ycor)
  let r compute-reward s s2
  set r (r + 50 * kills)

  update-q-table-egyptian s a r s2
end

;; =========================================
;; CANAL WAIT (ISRAELI ONLY)
;; =========================================

to handle-canal-wait
  if (canal-wait < 0) [
    ;; If we step onto the canal columns, start a short wait
    if (pxcor = canal-x - 1 or pxcor = canal-x or pxcor = canal-x + 1) [
      set canal-wait 5  ;; Reduced wait time from 10 to 5 ticks
      set canal-timer 0  ;; Reset the timer when entering the canal
    ]
  ]
  ;; Increment the timer when on the canal
  if (pxcor = canal-x - 1 or pxcor = canal-x or pxcor = canal-x + 1) [
    set canal-timer canal-timer + 1
  ]

  ;; Check if the agent has been on the canal for the required time
  if canal-timer >= 5 [
    set canal-wait -1  ;; Force the turtle to stop waiting on the canal
    set canal-timer 0  ;; Reset the timer
    set has-crossed-canal true  ;; Mark the unit as having crossed the canal
  ]
end

;; =========================================
;; ACTION SELECTION
;; =========================================

to-report choose-action-israeli [s]
  if (random-float 1 < epsilon) [
    report one-of ["move-north" "move-south" "move-east" "move-west"]
  ]
  report max-arg s "israeli"
end

to-report choose-action-egyptian [s]
  if (random-float 1 < epsilon) [
    report one-of ["move-north" "move-south" "move-east" "move-west"]
  ]
  report max-arg s "egyptian"
end

to-report max-arg [s side]
  let best-option "move-north"
  let best-value -99999
  let actions ["move-north" "move-south" "move-east" "move-west"]

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
end

;; =========================================
;; Q-VALUE LOOKUPS
;; =========================================

to-report q-value-israeli [s a]
  let entry filter [x -> (item 0 x = s and item 1 x = a)] q-table-israeli
  if empty? entry [report 0]
  report last first entry
end

to-report q-value-egyptian [s a]
  let entry filter [x -> (item 0 x = s and item 1 x = a)] q-table-egyptian
  if empty? entry [report 0]
  report last first entry
end

;; =========================================
;; MOVEMENT & REWARD
;; =========================================

to execute-action [a]
  if a = "move-north" [ set heading 0   fd 1 ]
  if a = "move-south" [ set heading 180 fd 1 ]
  if a = "move-east"  [ set heading 90  fd 1 ]
  if a = "move-west"  [ set heading 270 fd 1 ]
end

;; Hardcoded movement to the Chinese Farm
to move-toward-chinese-farm
  let target chinese-farm-center  ;; Target is the center of the Chinese Farm
  let delta-x [pxcor] of target - xcor  ;; Difference in x-coordinates
  let delta-y [pycor] of target - ycor  ;; Difference in y-coordinates

  ;; Move toward the target
  ifelse abs delta-x > abs delta-y [
    if delta-x > 0 [ set heading 90  fd 1 ]  ;; Move east
    if delta-x < 0 [ set heading 270 fd 1 ]  ;; Move west
  ]
  [
    if delta-y > 0 [ set heading 0   fd 1 ]  ;; Move north
    if delta-y < 0 [ set heading 180 fd 1 ]  ;; Move south
  ]
end

to-report compute-reward [s s2]
  let oldx item 0 s
  let newx item 0 s2
  let oldy item 1 s
  let newy item 1 s2

  ;; Base movement cost
  let reward -1

  ;; Reward for capturing Chinese Farm patches
  if [terrain-type] of patch newx newy = "chinese-farm" and [captured-by] of patch newx newy != team [
    set reward (reward + 1000)  ;; Large reward for capturing a patch
  ]

  ;; Penalty for staying idle or moving away from the Chinese Farm
  let target chinese-farm-center
  let target-x [pxcor] of target
  let target-y [pycor] of target
  let old-distance distancexy oldx oldy
  let new-distance distancexy newx newy
  if new-distance > old-distance [
    set reward (reward - 100)  ;; Penalty for moving away from the target
  ]

  ;; Missing REPORT statement here
  report reward
end

to update-q-table-israeli [s a r s2]
  let max-q max map [x -> q-value-israeli s2 x]
               ["move-north" "move-south" "move-east" "move-west"]
  let old-q q-value-israeli s a
  let q-update ((1 - alpha) * old-q) + (alpha * (r + gamma * max-q))
  set q-table-israeli update-q-entry q-table-israeli s a q-update
end

to update-q-table-egyptian [s a r s2]
  let max-q max map [x -> q-value-egyptian s2 x]
               ["move-north" "move-south" "move-east" "move-west"]
  let old-q q-value-egyptian s a
  let q-update ((1 - alpha) * old-q) + (alpha * (r + gamma * max-q))
  set q-table-egyptian update-q-entry q-table-egyptian s a q-update
end

to-report update-q-entry [table s a q-value]
  let new-table filter [row -> not (item 0 row = s and item 1 row = a)] table
  report lput (list s a q-value) new-table
end

;; =========================================
;; GROUP COHESION
;; =========================================

to-report my-group-center
  let mates turtles with [group-id = [group-id] of myself]
  if any? mates [
    let avg-x mean [xcor] of mates
    let avg-y mean [ycor] of mates
    report patch avg-x avg-y
  ]
  report patch-here
end

to report-unit-counts
  show (word "Israeli Units: " count turtles with [team = "israeli"])
  show (word "Egyptian Units: " count turtles with [team = "egyptian"])
end

;; =========================================
;; RANGED SHOOTING
;; =========================================

to check-shooting
  ;; 1) Infantry shoot enemy infantry in radius 3 (cannot shoot tanks)
  ask infantry [
    let targets infantry in-radius 3 with [team != [team] of myself]
    ask targets [
      die
      ask chinese-farm-patches with [captured-by = [team] of myself] [
        set captured-by "none"
        set pcolor green  ;; Reset color to green (neutral)
      ]
    ]
  ]

  ;; 2) Tanks shoot any enemy (tanks or infantry) in radius 5
  ask israeli-tanks [
    let targets turtles in-radius 5 with [team = "egyptian"]
    ask targets [
      die
      ask chinese-farm-patches with [captured-by = [team] of myself] [
        set captured-by "none"
        set pcolor green  ;; Reset color to green (neutral)
      ]
    ]
  ]
  ask egyptian-tanks [
    let targets turtles in-radius 5 with [team = "israeli"]
    ask targets [
      die
      ask chinese-farm-patches with [captured-by = [team] of myself] [
        set captured-by "none"
        set pcolor green  ;; Reset color to green (neutral)
      ]
    ]
  ]
end

to reset-crossing-status
  ask turtles [
    set has-crossed-canal false
  ]
end

to capture-chinese-farm
  ask turtles [
    if team = "israeli" [
      ask patch-here [
        if terrain-type = "chinese-farm" and captured-by != "israeli" [
          set captured-by "israeli"
          set pcolor blue  ;; Change color to blue for Israeli control
        ]
      ]
    ]
    if team = "egyptian" [
      ask patch-here [
        if terrain-type = "chinese-farm" and captured-by != "egyptian" [
          set captured-by "egyptian"
          set pcolor green  ;; Change color to green for Egyptian control
        ]
      ]
    ]
  ]
end

to-report distance-to-chinese-farm-center
  report distance chinese-farm-center
end

to-report team-distance [target-patch]
  ;; Check the team and position of the turtle
  ifelse team = "egyptian" [
    ;; Egyptians are on the west side, so only calculate distance if they are west of the canal
    if pxcor < canal-x [
      report distance target-patch
    ]
    ;; If Egyptians are on the east side, return a large distance (or handle as needed)
    report 9999  ;; Arbitrary large value to indicate invalid distance
  ]
  [
    ;; Israelis are on the east side, so only calculate distance if they are east of the canal
    if pxcor >= canal-x [
      report distance target-patch
    ]
    ;; If Israelis are on the west side, return a large distance (or handle as needed)
    report 9999  ;; Arbitrary large value to indicate invalid distance
  ]
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
