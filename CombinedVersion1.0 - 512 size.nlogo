;; =====================
;; COMBINED CODE (512 x 512, patch-size 2)
;; =====================

globals [
  battlefield-width
  battlefield-height

  ;; Terrain counters (from first file)
  water-patches
  canal-bank-patches
  sandy-patches
  desert-patches
  road-patches
  chinese-farm-patches

  ;; Q-learning globals (from second file)
  q-tables-israeli
  q-tables-egyptian
  i-alpha
  i-gamma
  i-epsilon
  e-alpha
  e-gamma
  e-epsilon
  kill-prob
  group-counter
  chinese-farm-center
  strategic-locations
  bridgehead-zone  ;; For the horizontal bridgehead zone
  bridgehead-controlled-by
]

breed [israeli-tanks israeli-tank]
breed [egyptian-tanks egyptian-tank]
breed [infantry soldier]

patches-own [
  final-color
  terrain-type
  captured-by
  is-strategic
  strategic-value
  defensive-bonus
  control-time
  fortified?
  mine?
  bridgehead?
]

turtles-own [
  state
  action
  team
  group-id
  defense-center  ;; Used for Egyptian defensive positioning
  last-state      ;; For death penalty updates
  last-action     ;; For death penalty updates
]

;------------------------------------------------
; SETUP
;------------------------------------------------
to setup
  clear-all

  ;; --------------------------------------------
  ;; 1) WORLD SIZE: 512 x 512
  ;; 2) PATCH SIZE: 2
  ;; --------------------------------------------
  set battlefield-width 512
  set battlefield-height 512
  resize-world 0 (battlefield-width - 1) 0 (battlefield-height - 1)
  set-patch-size 2

  ;; Initialize Q-learning parameters
  set i-alpha 0.5
  set i-gamma 0.5
  set i-epsilon 0.5
  set e-alpha 0.4
  set e-gamma 0.4
  set e-epsilon 0.4
  set kill-prob 0.5
  set q-tables-israeli []
  set q-tables-egyptian []
  set group-counter 0
  set strategic-locations []

  ;; -------------------------------------------------------
  ;; TERRAIN SETUP
  ;;  - Initialize all patches as sandy/desert-west FIRST
  ;; -------------------------------------------------------
  set water-patches 0
  set canal-bank-patches 0
  set sandy-patches 0
  set desert-patches 0
  set road-patches 0
  set chinese-farm-patches 0


  ;; Step A: Initialize everything to sandy color + desert-west
  ask patches [
    set final-color [230 239 184]  ;; sandy color
    set terrain-type "desert-west"
    set captured-by ""
    set is-strategic false
    set fortified? false
    set mine? false
    set bridgehead? false
    set defensive-bonus 0
    set control-time 0
    set strategic-value 0
  ]

  ;; Step B: Process each mask in turn
  set water-patches          process-mask "./Images/terrain_masks/water_mask.png"          [212 240 254]
  set canal-bank-patches     process-mask "./Images/terrain_masks/canal-bank_mask.png"     [208 229 172]
  set sandy-patches          process-mask "./Images/terrain_masks/sandy_mask.png"          [230 239 184]
  set desert-patches         process-mask "./Images/terrain_masks/desert_mask.png"         [255 229 202]
  set road-patches           process-mask "./Images/terrain_masks/road_mask.png"           [ 66  66  66]
  set chinese-farm-patches   process-mask "./Images/terrain_masks/chinese-farm_mask.png"   [  0 255   0]

  ;; Step C: Assign final pcolor to each patch & set terrain-type if changed
  ask patches [
    set pcolor final-color

    if final-color = [212 240 254] [
      set terrain-type "water"
    ]
    if final-color = [208 229 172] [  ;; canal-bank
      set terrain-type "desert-west"
    ]
    if final-color = [230 239 184] [  ;; sandy
      set terrain-type "desert-west"
    ]
    if final-color = [255 229 202] [  ;; desert
      set terrain-type "desert-west"
    ]
    if final-color = [ 66  66  66] [
      set terrain-type "road"
    ]
    if final-color = [  0 255   0] [
      set terrain-type "chinese-farm"
      set captured-by "none"
    ]
  ]


  ;; Identify the set of Chinese Farm patches
  set chinese-farm-patches patches with [ terrain-type = "chinese-farm" ]

  ;; Arbitrary reference center for Chinese Farm (same concept):
  set chinese-farm-center patch 40 50

  ;; ------------------------------------------------------------
  ;; 3) NEW STRATEGIC LOCATIONS (SCALED)
  ;;    Old: (405,916), (416,715), (530,442)
  ;;    New: (202,458), (208,358), (265,221)
  ;; ------------------------------------------------------------
  setup-strategic-locations

  ;; Define the bridgehead zone (unchanged)
  setup-bridgehead-zone

  ;; Setup Egyptian forces at the scaled strategic coords
  setup-egyptian-troops-on-strategic

  ;; Setup rest of the second file’s logic
  setup-units
  setup-fortified-lines
  setup-mines

  reset-ticks

  ;; Show final counts (optional)
  show (word "Number of water patches assigned: " water-patches)
  show (word "Number of canal-bank patches assigned: " canal-bank-patches)
  show (word "Number of sandy patches assigned: " sandy-patches)
  show (word "Number of desert patches assigned: " desert-patches)
  show (word "Number of road patches assigned: " road-patches)
  show (word "Number of Chinese farm patches assigned: " chinese-farm-patches)
end


;------------------------------------------------
; process-mask (unchanged from before)
;------------------------------------------------
to-report process-mask [mask-file rgb-list]
  import-pcolors mask-file
  let assigned 0
  ask patches [
    if pcolor = white [
      set final-color rgb-list
      set assigned assigned + 1
    ]
  ]
  report assigned
end

;------------------------------------------------
; Setup the Bridgehead Zone (unchanged)
;------------------------------------------------
to setup-bridgehead-zone
   set bridgehead-zone patches with [
     ; Custom polygon check with terrain type filter
     terrain-type = "chinese-farm" and
     in-polygon?
     (list
       (list 180 288)  ; First point
       (list 290 340)  ; Second point
       (list 280 315)  ; Third point
       (list 200 252)  ; Fourth point
     )
   ]
   ask bridgehead-zone [
     set pcolor magenta
     set bridgehead? true
     set strategic-value 15
   ]
end

to-report in-polygon? [polygon]
  let x pxcor
  let y pycor
  let inside? false
  let j (length polygon) - 1

  foreach range (length polygon) [ i ->
    let l item i polygon
    let pj item j polygon

    let xi item 0 l
    let yi item 1 l
    let xj item 0 pj
    let yj item 1 pj

    let intersect
      ((yi > y) != (yj > y)) and
      (x < (xj - xi) * (y - yi) / (yj - yi) + xi)

    if intersect [ set inside? (not inside?) ]
    set j i
  ]

  report inside?
end

;------------------------------------------------
; Setup the three strategic locations at half coords
;   (202,458), (208,358), (265,221)
;------------------------------------------------
to setup-strategic-locations
  create-strategic-location 210 320
  create-strategic-location 190 300
  create-strategic-location 240 325
end

to create-strategic-location [x y]
  let location-patches patches with [
    pxcor >= (x - 5) and pxcor <= (x + 5) and
    pycor >= (y - 5) and pycor <= (y + 5) and
    terrain-type = "chinese-farm"
  ]
  ask location-patches [
    set is-strategic true
    set pcolor violet
    set strategic-value 5
  ]
  set strategic-locations (patch-set strategic-locations location-patches)
end

;;------------------------------------------------
;; Setup Egyptian Troops on the new strategic coords
;;   (202, 458), (208, 358), (265, 221)
;;------------------------------------------------
;to setup-egyptian-troops-on-strategic
;
;  ;; Strategic Location 1: (202,458)
;  create-egyptian-tanks 60 [
;    set group-id group-counter
;    set team "egyptian"
;    set shape "triangle"
;    set color 25
;    setxy 202 458
;    set state (list xcor ycor)
;    set action "hold-position"
;    set size 1.5
;  ]
;  set group-counter group-counter + 1
;
;  create-infantry 50 [
;    set group-id group-counter
;    set team "egyptian"
;    set shape "person"
;    set color 15
;    setxy 202 458
;    set state (list xcor ycor)
;    set action "hold-position"
;    set size 1.5
;  ]
;  set group-counter group-counter + 1
;
;  ;; Strategic Location 2: (208,358)
;  create-egyptian-tanks 50 [
;    set group-id group-counter
;    set team "egyptian"
;    set shape "triangle"
;    set color 25
;    setxy 208 358
;    set state (list xcor ycor)
;    set action "hold-position"
;    set size 1.5
;  ]
;  set group-counter group-counter + 1
;
;  create-infantry 40 [
;    set group-id group-counter
;    set team "egyptian"
;    set shape "person"
;    set color 15
;    setxy 208 358
;    set state (list xcor ycor)
;    set action "hold-position"
;    set size 1.5
;  ]
;  set group-counter group-counter + 1
;
;  ;; Strategic Location 3: (265,221)
;  create-egyptian-tanks 40 [
;    set group-id group-counter
;    set team "egyptian"
;    set shape "triangle"
;    set color 25
;    setxy 265 221
;    set state (list xcor ycor)
;    set action "hold-position"
;    set size 1.5
;  ]
;  set group-counter group-counter + 1
;
;  create-infantry 35 [
;    set group-id group-counter
;    set team "egyptian"
;    set shape "person"
;    set color 15
;    setxy 265 221
;    set state (list xcor ycor)
;    set action "hold-position"
;    set size 1.5
;  ]
;  set group-counter group-counter + 1
;end

to setup-egyptian-troops-on-strategic
  ;; e.g., one big batch of 60 tanks around (200,350)
  create-egyptian-tanks 75 [
    set group-id group-counter
    set team "egyptian"
    set shape "triangle"
    set color 25
    ;; random within ±20 of (200,350)
    let rx (210 - 10 + random 20)
    let ry (310 - 10 + random 20)
    setxy rx ry
    set state (list xcor ycor)
    set action "hold-position"
    set size 1.5
  ]
  set group-counter group-counter + 1

   create-egyptian-tanks 50 [
    set group-id group-counter
    set team "egyptian"
    set shape "triangle"
    set color 25
    ;; random within ±20 of (200,350)
    let rx (190 - 10 + random 20)
    let ry (300 - 10 + random 20)
    setxy rx ry
    set state (list xcor ycor)
    set action "hold-position"
    set size 1.5
  ]
  set group-counter group-counter + 1

   create-egyptian-tanks 50 [
    set group-id group-counter
    set team "egyptian"
    set shape "triangle"
    set color 25
    ;; random within ±20 of (200,350)
    let rx (240 - 10 + random 20)
    let ry (325 - 10 + random 20)
    setxy rx ry
    set state (list xcor ycor)
    set action "hold-position"
    set size 1.5
  ]
  set group-counter group-counter + 1


  ;; e.g., another batch of 50 infantry around the same region
  create-infantry 150 [
    set group-id group-counter
    set team "egyptian"
    set shape "person"
    set color 15
    let rx (240 - 10 + random 20)
    let ry (325 - 10 + random 20)
    setxy rx ry
    set state (list xcor ycor)
    set action "hold-position"
    set size 1.5
  ]
  set group-counter group-counter + 1

  create-infantry 150 [
    set group-id group-counter
    set team "egyptian"
    set shape "person"
    set color 15
    let rx (225 - 10 + random 20)
    let ry (300 - 10 + random 20)
    setxy rx ry
    set state (list xcor ycor)
    set action "hold-position"
    set size 1.5
  ]
  set group-counter group-counter + 1
end

;------------------------------------------------
; Setup Israeli Units, Fortifications, Mines, etc.
; (unchanged from the second file)
;------------------------------------------------
to setup-units
  ;; Israeli Tanks: 5 groups of 5
  repeat 10 [
;    let cluster-x (25 + random 15)
;    let cluster-y (5 + random 5)
     let cluster-x (300 - 15 + random 31)  ; random integer in [285..315]
     let cluster-y (300 - 15 + random 31)
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

  repeat 10 [
;    let cluster-x (25 + random 15)
;    let cluster-y (5 + random 5)
     let cluster-x (250 - 15 + random 31)  ; random integer in [285..315]
     let cluster-y (250 - 15 + random 31)
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

  repeat 20 [
;    let cluster-x (25 + random 15)
;    let cluster-y (5 + random 5)
     let cluster-x (250 - 15 + random 31)
     let cluster-y (250 - 15 + random 31)
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

  ;; Israeli Infantry: 5 groups of 5
  repeat 50 [
;    let cluster-x (25 + random 15)
;    let cluster-y (5 + random 5)
     let cluster-x (300 - 15 + random 31)
     let cluster-y (300 - 15 + random 31)
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
end

to go
  ask israeli-tanks [ q-learn-move-israeli ]
  ask egyptian-tanks [ q-learn-move-egyptian ]
  ask infantry with [team = "israeli"] [ q-learn-move-israeli-infantry ]
  ask infantry with [team = "egyptian"] [ q-learn-move-egyptian-infantry ]
  capture-chinese-farm
  reinforce-chinese-farm
  check-win-condition
  check-landmines
  ;;show (word "Israeli Units: " count turtles with [team = "israeli"])
  ;;show (word "Egyptian Units: " count turtles with [team = "egyptian"])
  tick
end

;------------------------------------------------
; Q-LEARNING FOR ISRAELI UNITS
;------------------------------------------------
to q-learn-move-israeli
  ; Record the current state and chosen action for later use (e.g., in death penalty)
  let s (list xcor ycor)
  set last-state s
  let a choose-action-israeli s
  set last-action a

  let oldx xcor
  let oldy ycor

  ; Check if unit is stuck (minimal movement) and force a random move
  if (distancexy oldx oldy) < 0.1 and random-float 1 < 0.3 [
    set heading random 360
    fd 1
  ]

  ;; Check for nearby strategic locations
  let nearby-strategic-patches strategic-locations in-radius 40
  ifelse any? nearby-strategic-patches and random-float 1 < 0.7 [
    ;; If strategic locations are nearby, move toward the closest one
    let target min-one-of nearby-strategic-patches [distance myself]
    if target != nobody [
      face target
      fd 1.5  ;; Move faster toward strategic locations
    ]
  ][
    ;; Otherwise, follow original movement logic:
    ifelse [terrain-type] of patch-here != "chinese-farm" [
      move-toward-chinese-farm
    ]
    [
      ; If within the Chinese Farm, check for nearby enemy units
      ifelse any? turtles with [team = "egyptian"] in-radius 3 [
        let target min-one-of turtles with [team = "egyptian"] [distance myself]
        if target != nobody [
          face target
          fd 1
        ]
      ]
      [
        ; If no enemy nearby, execute the chosen action
        execute-action a

        ; Try to move toward nearby uncaptured territory if needed
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

  ; Keep unit close to its group (do not stray too far)
  if distance my-group-center > 5 [ setxy oldx oldy ]

  ; Attack nearby Egyptian enemy units and apply death penalty if they are hit
  ask egyptian-tanks in-radius 2 [
    if random-float 1 < kill-prob [ penalize-death ]
  ]
  ask infantry with [team = "egyptian"] in-radius 2 [
    if random-float 1 < kill-prob [ penalize-death ]
  ]

  let s2 (list xcor ycor)
  let r compute-reward s s2

  ; Add bonus reward for capturing territory with a special bonus for strategic locations
  if [terrain-type] of patch-here = "chinese-farm" and [captured-by] of patch-here != "israeli" [
    ifelse [is-strategic] of patch-here [
      set r r + 2000  ;; Higher bonus for strategic locations
      ;;show (word "Israeli unit " who " captured a strategic location!")
    ][
      set r r + 1000  ;; Regular bonus for standard patches
    ]
  ]

  update-q-table-israeli s a r s2
end

;------------------------------------------------
; Q-LEARNING FOR EGYPTIAN TANKS
;------------------------------------------------
to q-learn-move-egyptian
  ; Record current state and chosen action
  let s (list xcor ycor)
  set last-state s
  let a choose-action-egyptian s
  set last-action a

  let oldx xcor
  let oldy ycor

  ; If in "hold-position" mode, adjust movement accordingly
  if action = "hold-position" [
    if [terrain-type] of patch-here != "chinese-farm" [
      move-toward-chinese-farm
      stop
    ]
    if (not is-list? defense-center) or (defense-center = 0) [
      set defense-center (list xcor ycor)
    ]
    let strategic-israeli-captured strategic-locations with [captured-by = "israeli"] in-radius 40
    ifelse any? strategic-israeli-captured [
      ;;show (word "Egyptian tank " who " detected captured strategic location!")
      set action "surround"
    ][
      ifelse any? turtles with [team = "israeli"] in-radius 10 [
        ;;show (word "Egyptian tank " who " detected an Israeli unit!")
        set action "surround"
      ][
        let israeli-captured-nearby patches in-radius 12 with [terrain-type = "chinese-farm" and captured-by = "israeli"]
        ifelse any? israeli-captured-nearby [
          ;;show (word "Egyptian tank " who " moving to recapture territory!")
          face min-one-of israeli-captured-nearby [distance myself]
          fd 1.5
          if random-float 1 < 0.3 [
            set action "surround"
          ]
        ][
          ifelse random-float 1 < 0.7 [
            rt (random 40 - 20)
            fd 0.75
            if distancexy (item 0 defense-center) (item 1 defense-center) > 7 [
              face patch (item 0 defense-center) (item 1 defense-center)
              fd 1
            ]
          ][
            rt (random 90 - 45)
            fd 1.5
          ]
        ]
        stop
      ]
    ]
  ]

  ; Regular movement for Egyptian tanks
  let strategic-targets strategic-locations with [captured-by = "israeli" or captured-by = "none"] in-radius 40
  ifelse any? strategic-targets and random-float 1 < 0.8 [
    let target min-one-of strategic-targets [distance myself]
    if target != nobody [
      face target
      fd 2
      ;;show (word "Egyptian tank " who " moving toward strategic location!")
    ]
  ][
    let nearby-israeli-tanks israeli-tanks in-radius 10
    let nearby-israeli-infantry infantry with [team = "israeli"] in-radius 15
    ifelse any? nearby-israeli-tanks or any? nearby-israeli-infantry [
      let nearest-enemy min-one-of (turtle-set nearby-israeli-tanks nearby-israeli-infantry) [ distance myself ]
      if nearest-enemy != nobody [
        set a "surround"
        face nearest-enemy
        fd 1.25
      ]
    ]
    [
      let israeli-captured patches in-radius 15 with [terrain-type = "chinese-farm" and captured-by = "israeli"]
      ifelse any? israeli-captured [
        face min-one-of israeli-captured [distance myself]
        fd 2
        if [terrain-type] of patch-here = "chinese-farm" [
          ask patch-here [
            set captured-by "egyptian"
            set pcolor green
          ]
        ]
      ]
      [
        ifelse [terrain-type] of patch-here != "chinese-farm" [
          move-toward-chinese-farm
        ]
        [
          ifelse random-float 1 < 0.6 [
            execute-action "defend"
          ]
          [
            execute-action a
            if random-float 1 < 0.15 [
              rt (random 180 - 90)
              fd 1.5
            ]
          ]
          if distance my-group-center > 8 [
            face my-group-center
            fd 1
          ]
        ]
      ]
    ]
  ]

  if action = "hold-position" and random-float 1 < 0.85 [
    set action "hold-position"
  ]

  let kills 0
  ask israeli-tanks in-radius 2 [
    if random-float 1 < kill-prob [
      penalize-death
      set kills kills + 1
    ]
  ]
  ask infantry with [team = "israeli"] in-radius 2 [
    if random-float 1 < kill-prob [
      penalize-death
      set kills kills + 1
    ]
  ]

  let s2 (list xcor ycor)
  let r compute-reward s s2

  set r (r + 50 * kills)
  if [terrain-type] of patch-here = "chinese-farm" and [captured-by] of patch-here = "israeli" [
    ifelse [is-strategic] of patch-here [
      set r r + 2000
      ;;show (word "Egyptian tank " who " recaptured a strategic location!")
    ][
      set r r + 1000
    ]
  ]

  update-q-table-egyptian s a r s2
end

;------------------------------------------------
; Q-LEARNING FOR ISRAELI INFANTRY
;------------------------------------------------
to q-learn-move-israeli-infantry
  ; Record current state and chosen action
  let s (list xcor ycor)
  set last-state s
  let a choose-action-israeli s
  set last-action a

  let oldx xcor
  let oldy ycor

  ;; Check for nearby strategic locations
  let nearby-strategic-patches strategic-locations in-radius 40
  ifelse any? nearby-strategic-patches and random-float 1 < 0.7 [
    let target min-one-of nearby-strategic-patches [distance myself]
    if target != nobody [
      face target
      fd 1.5
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

  ; Attack nearby Egyptian infantry with death penalty applied
  ask infantry with [team = "egyptian"] in-radius 5 [
    if random-float 1 < kill-prob [ penalize-death ]
  ]

  let s2 (list xcor ycor)
  let r compute-reward s s2

  ; Bonus reward for capturing territory
  if [terrain-type] of patch-here = "chinese-farm" and [captured-by] of patch-here != "israeli" [
    ifelse [is-strategic] of patch-here [
      set r r + 1500
      ;;show (word "Israeli infantry " who " captured a strategic location!")
    ][
      set r r + 750
    ]
  ]

  update-q-table-israeli s a r s2
end

;------------------------------------------------
; Q-LEARNING FOR EGYPTIAN INFANTRY
;------------------------------------------------
to q-learn-move-egyptian-infantry
  ; Record current state and chosen action
  let s (list xcor ycor)
  set last-state s
  let a choose-action-egyptian s
  set last-action a

  let oldx xcor
  let oldy ycor

  if action = "hold-position" [
    if [terrain-type] of patch-here != "chinese-farm" [
      move-toward-chinese-farm
      stop
    ]
    if (not is-list? defense-center) or (defense-center = 0) [
      set defense-center (list xcor ycor)
    ]
    let strategic-israeli-captured strategic-locations with [captured-by = "israeli"] in-radius 40
    ifelse any? strategic-israeli-captured [
      ;;show (word "Egyptian infantry " who " detected captured strategic location!")
      set action "surround"
    ][
      ifelse any? turtles with [team = "israeli"] in-radius 7 [
        ;show (word "Egyptian infantry " who " detected an Israeli unit!")
        set action "surround"
      ][
        let israeli-captured-nearby patches in-radius 10 with [terrain-type = "chinese-farm" and captured-by = "israeli"]
        ifelse any? israeli-captured-nearby [
          ;;show (word "Egyptian infantry " who " moving to recapture territory!")
          face min-one-of israeli-captured-nearby [distance myself]
          fd 1.25
          if random-float 1 < 0.3 [
            set action "surround"
          ]
        ][
          rt (random 40 - 20)
          fd 0.75
          if distancexy (item 0 defense-center) (item 1 defense-center) > 7 [
            face patch (item 0 defense-center) (item 1 defense-center)
            fd 1
          ]
        ]
        stop
      ]
    ]
  ]

  let strategic-targets strategic-locations with [captured-by = "israeli" or captured-by = "none"] in-radius 40
  ifelse any? strategic-targets and random-float 1 < 0.8 [
    let target min-one-of strategic-targets [distance myself]
    if target != nobody [
      face target
      fd 1.75
      ;;show (word "Egyptian infantry " who " moving toward strategic location!")
    ]
  ][
    let nearby-israeli-tanks israeli-tanks in-radius 10
    let nearby-israeli-infantry infantry with [team = "israeli"] in-radius 12
    ifelse any? nearby-israeli-tanks or any? nearby-israeli-infantry [
      let nearest-enemy min-one-of (turtle-set nearby-israeli-tanks nearby-israeli-infantry) [distance myself]
      if nearest-enemy != nobody [
        set a "surround"
        face nearest-enemy
        fd 1.25
      ]
    ]
    [
      let israeli-captured patches in-radius 15 with [terrain-type = "chinese-farm" and captured-by = "israeli"]
      ifelse any? israeli-captured [
        face min-one-of israeli-captured [distance myself]
        fd 1.5
        if [terrain-type] of patch-here = "chinese-farm" [
          ask patch-here [
            set captured-by "egyptian"
            set pcolor green
          ]
        ]
      ]
      [
        ifelse [terrain-type] of patch-here != "chinese-farm" [
          move-toward-chinese-farm
        ]
        [
          ifelse random-float 1 < 0.6 [
            execute-action "defend"
          ]
          [
            execute-action a
            if random-float 1 < 0.15 [
              rt (random 180 - 90)
              fd 1.5
            ]
          ]
          if distance my-group-center > 8 [
            face my-group-center
            fd 1
          ]
        ]
      ]
    ]
  ]

  if action = "hold-position" and random-float 1 < 0.85 [
    set action "hold-position"
  ]

  let kills 0
  ask israeli-tanks in-radius 3 [
    if random-float 1 < kill-prob [
      penalize-death
      set kills kills + 1
    ]
  ]
  ask infantry with [team = "israeli"] in-radius 3 [
    if random-float 1 < kill-prob [
      penalize-death
      set kills kills + 1
    ]
  ]

  let s2 (list xcor ycor)
  let r compute-reward s s2

  set r (r + 50 * kills)
  if [terrain-type] of patch-here = "chinese-farm" and [captured-by] of patch-here = "israeli" [
    ifelse [is-strategic] of patch-here [
      set r r + 1500
      ;;show (word "Egyptian infantry " who " recaptured a strategic location!")
    ][
      set r r + 750
    ]
  ]

  update-q-table-egyptian s a r s2
end

;------------------------------------------------
; ACTION SELECTION & Q-VALUE LOOKUPS
;------------------------------------------------
to-report choose-action-israeli [s]
  if ticks < 75 [
    if (random-float 1 < i-epsilon) [
      report one-of ["move-north" "move-south" "move-east" "move-west"]
    ]
    report max-arg-group s group-id "israeli"
  ]
  if ticks >= 75 [
    if (random-float 1 < i-epsilon) [
      report one-of ["move-north" "move-south" "move-east" "move-west" "protect bridgehead"]
    ]
    report max-arg-group s group-id "israeli"
  ]
end

to-report choose-action-egyptian [s]
  if (random-float 1 < e-epsilon) [
    report one-of ["move-north" "move-south" "move-east" "move-west" "defend" "surround"]
  ]
  report max-arg-group s group-id "egyptian"
end

to-report q-value-israeli-group [g s a]
  let qtable get-q-table-israeli g
  let entry filter [x -> (item 0 x = s and item 1 x = a)] qtable
  if empty? entry [
    ifelse a = "protect bridgehead" [
      report 100000  ;; high initial value for protect bridgehead
    ][
      report 0
    ]
  ]
  report last first entry
end

to-report q-value-egyptian-group [g s a]
  let qtable get-q-table-egyptian g
  let entry filter [x -> (item 0 x = s and item 1 x = a)] qtable
  if empty? entry [ report 0 ]
  report last first entry
end

to-report max-arg-group [s g side]
  let actions []
  if side = "egyptian" [
    ifelse ticks < 75 [
      set actions ["move-north" "move-south" "move-east" "move-west" "defend" "surround"]
    ][
    set actions ["move-north" "move-south" "move-east" "move-west" "defend" "surround" "stop bridgehead"]
  ]
  ]
  if side = "israeli" [
  ifelse ticks < 75 [
    set actions ["move-north" "move-south" "move-east" "move-west"]
  ] [
    set actions ["move-north" "move-south" "move-east" "move-west" "protect bridgehead"]
  ]
]
  let best-option first actions
  let best-value -99999
  foreach actions [ a ->
    let v ifelse-value (side = "israeli") [
      q-value-israeli-group g s a
    ] [
      q-value-egyptian-group g s a
    ]
    if v > best-value [
      set best-option a
      set best-value v
    ]
  ]
  report best-option
end

to-report q-value-israeli [s a]
  let entry filter [x -> (item 0 x = s and item 1 x = a)] q-tables-israeli
  if empty? entry [ report 0 ]
  report last first entry
end

to-report q-value-egyptian [s a]
  let entry filter [x -> (item 0 x = s and item 1 x = a)] q-tables-egyptian
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
    let nearest-enemy min-one-of turtles with [ team = "israeli" ] [ distance myself ]
    if nearest-enemy != nobody [
      face nearest-enemy
      if distance nearest-enemy < 3 [ fd 1 ]
    ]
  ]

  if a = "surround" [
    let target min-one-of turtles with [ team = "israeli" ] [ distance myself ]
    if target != nobody [
      let long-attack-range 6
      if distance target <= long-attack-range [
        face target
        if random-float 1 < kill-prob [ ask target [ die ] ]
      ]
      if distance target > long-attack-range [
        set heading towards target
        fd 1.5
      ]
    ]
    if target = nobody [
  let israeli-captured patches in-radius 15 with [ terrain-type = "chinese-farm" and captured-by = "israeli" ]
  ifelse any? israeli-captured [
    face min-one-of israeli-captured [ distance myself ]
    fd 1.5
  ] [
    rt (random 90 - 45)
    fd 1
  ]
]
  ]

  ;; Egyptian action for bridgehead defense using the horizontal line
  if a = "stop bridgehead" [
    let bh-patch min-one-of bridgehead-zone [ distance myself ]
    face bh-patch
    fd 1.5
    if any? turtles with [ team = "israeli" ] in-radius 3 [
      ask turtles with [ team = "israeli" ] in-radius 3 [
        if random-float 1 < kill-prob [ penalize-death ]
      ]
    ]
  ]

  ;; Israeli action for protecting the bridgehead (available after tick 50)
  if a = "protect bridgehead" [
  let bh-patch min-one-of bridgehead-zone [ distance myself ]
  face bh-patch
  ifelse distance bh-patch > 2 [
    fd 1.5
  ] [
    rt (random 20 - 10)
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
  let r 0

  if team = "israeli" [
    ;; existing Israeli reward calculations...
    let old-dist distance chinese-farm-center
    let new-dist sqrt (((newx - [pxcor] of chinese-farm-center) ^ 2) + ((newy - [pycor] of chinese-farm-center) ^ 2))
    set r r + ifelse-value (new-dist < old-dist) [10] [0]
    if [terrain-type] of patch newx newy = "chinese-farm" [
      set r r + 50
      if [is-strategic] of patch newx newy [
        set r r + (100 * [strategic-value] of patch newx newy)
      ]
    ]
    let nearby-enemies count turtles with [team = "egyptian"] in-radius 3
    set r r + (nearby-enemies * 20)
    let israeli-control count chinese-farm-patches with [captured-by = "israeli"]
    let control-pct (israeli-control / count chinese-farm-patches) * 100
    set r r + (control-pct / 10)
  ]

  if team = "egyptian" [
    ;; existing Egyptian reward calculation...
    if [terrain-type] of patch newx newy = "chinese-farm" [
      set r r + 30
      if [is-strategic] of patch newx newy [
        set r r + (75 * [strategic-value] of patch newx newy)
      ]
    ]
    let nearby-enemies count turtles with [team = "israeli"] in-radius 3
    set r r + (nearby-enemies * 25)
    let egyptian-control count chinese-farm-patches with [captured-by = "egyptian"]
    let control-pct (egyptian-control / count chinese-farm-patches) * 100
    set r r + (control-pct / 5)
    if [fortified?] of patch newx newy [
      set r r + 1500
    ]

    ;; NEW: Bridgehead zone bonus:
    if member? patch newx newy bridgehead-zone [
      ;; Base bonus of 1000 plus a time-dependent component.
      set r r + 1000 + (ticks * 20)
    ]
  ]

  report r
end

to update-q-table-israeli [s a r s2]
  let g group-id  ; use the turtle's group-id
  let next-action max-arg-group s2 g "israeli"
  let old-q q-value-israeli-group g s a
  let next-q q-value-israeli-group g s2 next-action
  let new-q (old-q + i-alpha * (r + i-gamma * next-q - old-q))

  ;; Boost the Q value if the action is "protect bridgehead"
  if a = "protect bridgehead" [
    ;; Add a bonus that grows over time
    set new-q new-q + (ticks * 50)
    ;; And if the unit is not actually in the bridgehead zone, apply a penalty
    if not member? patch-here bridgehead-zone [
      set new-q new-q - 1000
    ]
  ]

  ;; Optional: boost Q value when on any strategic patch
  if [is-strategic] of patch-here [
    set new-q new-q * 1.25
  ]

  let qtable get-q-table-israeli g
  let new-table update-q-entry qtable s a new-q
  set-q-table-israeli g new-table
end

to update-q-table-egyptian [s a r s2]
  let g group-id  ; use the turtle's group-id for the Egyptian Q-table
  let next-action max-arg-group s2 g "egyptian"
  let old-q q-value-egyptian-group g s a
  let next-q q-value-egyptian-group g s2 next-action
  let new-q (old-q + e-alpha * (r + e-gamma * next-q - old-q))

  ; Bonus: boost Q-value for strategic patches (Egyptians value these even more)
  if [is-strategic] of patch-here [
    set new-q new-q * 1.3
  ]

  let qtable get-q-table-egyptian g
  let new-table update-q-entry qtable s a new-q
  set-q-table-egyptian g new-table
end

; Enhanced capture function that considers strategic locations
to capture-chinese-farm
  ;; Update bridgehead status tracking (keep this part the same)
  let israeli-bh-count count bridgehead-zone with [captured-by = "israeli"]
  let egyptian-bh-count count bridgehead-zone with [captured-by = "egyptian"]

  ifelse israeli-bh-count > egyptian-bh-count [
    set bridgehead-controlled-by "israeli"
  ] [
    if egyptian-bh-count > 0 [
      set bridgehead-controlled-by "egyptian"
    ]
  ]

  ;; Modify the Israeli capture section like this:
  ask turtles [
    if team = "israeli" [
      ask patch-here [
        if terrain-type = "chinese-farm" [
          if member? self bridgehead-zone and captured-by != "israeli" [
            set captured-by "israeli"
            set pcolor blue + 2 ;; Light blue for Israeli bridgehead
            set control-time 0
          ]
          if (not member? self bridgehead-zone) and captured-by != "israeli" [
            ifelse is-strategic [
              set captured-by "israeli"
              set pcolor orange
              set control-time 0
            ][
              set captured-by "israeli"
              set pcolor brown
            ]
          ]
        ]
      ]
    ]

    ;; Keep the Egyptian capture logic the same
    if team = "egyptian" [
      ask patch-here [
        if terrain-type = "chinese-farm" [
          if not fortified? [
            if ticks >= 75 and member? self bridgehead-zone [
              set captured-by "egyptian"
              set pcolor turquoise ;; Egyptian bridgehead color stays turquoise
              set control-time 0
            ]
            if not member? self bridgehead-zone [
              ifelse is-strategic [
                set captured-by "egyptian"
                set pcolor turquoise
                set control-time 0
              ][
                set captured-by "egyptian"
                set pcolor green
              ]
            ]
          ]
        ]
      ]
    ]
  ]
end

; Enhanced to prioritize strategic locations
to reinforce-chinese-farm
  ;; --- Egyptian Tanks ---
  ask egyptian-tanks [
    if ticks >= 75 [
      ifelse any? bridgehead-zone with [ captured-by != "egyptian" ] in-radius 20 [
        let target min-one-of bridgehead-zone with [ captured-by != "egyptian" ] [ distance myself ]
        if target != nobody [
          face target
          fd 2  ; move faster toward the bridgehead
          ;show (word "Egyptian tank " who " moving to invade the bridgehead!")
        ]
      ] [
        ;; Fallback standard behavior if no bridgehead patch available
        ifelse any? turtles with [ team = "israeli" ] in-radius 5 [
          let target min-one-of turtles with [ team = "israeli" ] [ distance myself ]
          if target != nobody [
            face target
            fd 1
          ]
        ] [
          let israeli-patches patches in-radius 15 with [ terrain-type = "chinese-farm" and captured-by = "israeli" ]
          ifelse any? israeli-patches [
  face min-one-of israeli-patches [ distance myself ]
  fd 1.5
] [
  if random-float 1 < 0.2 [
    rt (random 90 - 45)
    fd 1
  ]
]
        ]
      ]
    ]
    if ticks < 75 [
      ;; Standard behavior before tick 20
      ifelse any? turtles with [ team = "israeli" ] in-radius 5 [
        let target min-one-of turtles with [ team = "israeli" ] [ distance myself ]
        if target != nobody [
          face target
          fd 1
        ]
      ] [
        let captured-patches patches in-radius 15 with [ terrain-type = "chinese-farm" and captured-by = "israeli" ]
        ifelse any? captured-patches [
  face min-one-of captured-patches [ distance myself ]
  fd 1.5
] [
  if random-float 1 < 0.2 [
    rt (random 90 - 45)
    fd 1
  ]
]
      ]
    ]
  ]

  ;; --- Egyptian Infantry ---
  ask infantry with [ team = "egyptian" ] [
    if ticks >= 75 [
      ifelse any? bridgehead-zone with [ captured-by != "egyptian" ] in-radius 15 [
        let target min-one-of bridgehead-zone with [ captured-by != "egyptian" ] [ distance myself ]
        if target != nobody [
          face target
          fd 1.5
          ;show (word "Egyptian infantry " who " invading the bridgehead!")
        ]
      ] [
        ;; Fallback behavior for infantry
        ifelse any? turtles with [ team = "israeli" ] in-radius 7 [
          let target min-one-of turtles with [ team = "israeli" ] [ distance myself ]
          if target != nobody [
            face target
            fd 1.25
          ]
        ] [
          let captured-patches patches in-radius 10 with [ terrain-type = "chinese-farm" and captured-by = "israeli" ]
          ifelse any? captured-patches [
  face min-one-of captured-patches [ distance myself ]
  fd 1.5
] [
  rt (random 40 - 20)
  fd 0.75
]
        ]
      ]
    ]
    if ticks < 75 [
      ;; Standard behavior before tick 20
      ifelse any? turtles with [ team = "israeli" ] in-radius 7 [
        let target min-one-of turtles with [ team = "israeli" ] [ distance myself ]
        if target != nobody [
          face target
          fd 1.25
        ]
      ] [
        let captured-patches patches in-radius 10 with [ terrain-type = "chinese-farm" and captured-by = "israeli" ]
        ifelse any? captured-patches [
  face min-one-of captured-patches [ distance myself ]
  fd 1.5
] [
  rt (random 40 - 20)
  fd 0.75
]
      ]
    ]
  ]

  ;; --- (Optional) Israeli Reinforcement ---
  ask turtles with [ team = "israeli" ] [
    let target-strategic (patch-set (patches with [ captured-by = "egyptian" ]) (patches with [ captured-by = "none" ]))
    if any? target-strategic in-radius 20 [
      let target min-one-of target-strategic [ distance myself ]
      if target != nobody and random-float 1 < 0.7 [
        face target
        fd 1.75
        ;show (word "Israeli unit " who " moving to capture strategic location!")
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
    let effective-kill-prob kill-prob
    if [is-strategic] of patch-here and [captured-by] of patch-here = team [
      set effective-kill-prob kill-prob * (1 - [defensive-bonus] of patch-here)
      if effective-kill-prob < 0.1 [ set effective-kill-prob 0.1 ]
    ]
    ;; NEW: If the shooter is on a fortified patch, double the accuracy.
    if [fortified?] of patch-here [
      set effective-kill-prob effective-kill-prob * 2
      if effective-kill-prob > 1 [ set effective-kill-prob 1 ]
    ]
    if random-float 1 < effective-kill-prob [ die ]
  ]
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


to ensure-q-table-israeli [g]
  while [g >= length q-tables-israeli] [
    set q-tables-israeli lput [] q-tables-israeli
  ]
end

to-report get-q-table-israeli [g]
  ensure-q-table-israeli g
  report item g q-tables-israeli
end

to set-q-table-israeli [g new-table]
  ensure-q-table-israeli g
  set q-tables-israeli replace-item g q-tables-israeli new-table
end

to ensure-q-table-egyptian [g]
  while [g >= length q-tables-egyptian] [
    set q-tables-egyptian lput [] q-tables-egyptian
  ]
end

to-report get-q-table-egyptian [g]
  ensure-q-table-egyptian g
  report item g q-tables-egyptian
end

to set-q-table-egyptian [g new-table]
  ensure-q-table-egyptian g
  set q-tables-egyptian replace-item g q-tables-egyptian new-table
end

to penalize-death
  ;; Use stored last-state and last-action if available, otherwise use current state and action
  let s (ifelse-value (not (empty? last-state)) [ last-state ] [ (list xcor ycor) ])
  let a (ifelse-value (last-action != "") [ last-action ] [ action ])
  let s2 (list xcor ycor)  ;; Next state is current (dead) position
  if team = "israeli" [
    update-q-table-israeli s a -1000 s2
  ]
  if team = "egyptian" [
    update-q-table-egyptian s a -1000 s2
  ]
  die
end

to focused-epsilon-search
  ;; Fixed parameters for other variables
  set e-alpha 0.5  ;; Fixed learning rate
  set e-gamma 0.5  ;; Fixed discount factor

  ;; Exploration values to test
  let epsilon-values [0.1 0.3 0.5 0.7 0.9]
  let results []

  foreach epsilon-values [ ee ->
    set e-epsilon ee
    let trial-results []

    repeat 5 [
      ;; 1. SETUP - but don't record initial counts yet
      setup

      ;; 2. RECORD INITIAL COUNTS AFTER SETUP BUT BEFORE SIMULATION
      let initial-israeli-tanks count israeli-tanks
      let initial-egyptian-tanks count egyptian-tanks
      let initial-israeli-inf count infantry with [team = "israeli"]
      let initial-egyptian-inf count infantry with [team = "egyptian"]

      ;; 3. RUN SIMULATION
      repeat 150 [ go ]

      ;; 4. CALCULATE LOSSES (current count is automatically post-simulation)
      let israeli-tanks-lost (initial-israeli-tanks - count israeli-tanks)
      let egyptian-tanks-lost (initial-egyptian-tanks - count egyptian-tanks)
      let israeli-inf-lost (initial-israeli-inf - count infantry with [team = "israeli"])
      let egyptian-inf-lost (initial-egyptian-inf - count infantry with [team = "egyptian"])

      ;; Rest of your data collection...
      let bh-total count bridgehead-zone
      let bh-israeli count bridgehead-zone with [captured-by = "israeli"]
      let bh-egyptian count bridgehead-zone with [captured-by = "egyptian"]
      let bh-israeli-pct (bh-israeli / max (list 1 bh-total)) * 100
      let bh-egyptian-pct (bh-egyptian / max (list 1 bh-total)) * 100

      let cf-total count chinese-farm-patches
      let cf-israeli count chinese-farm-patches with [captured-by = "israeli"]
      let cf-egyptian count chinese-farm-patches with [captured-by = "egyptian"]
      let cf-israeli-pct (cf-israeli / max (list 1 cf-total)) * 100
      let cf-egyptian-pct (cf-egyptian / max (list 1 cf-total)) * 100

      set trial-results lput (list
        israeli-tanks-lost egyptian-tanks-lost
        israeli-inf-lost egyptian-inf-lost
        bh-israeli-pct bh-egyptian-pct
        cf-israeli-pct cf-egyptian-pct
      ) trial-results
    ]

    set results lput (list ee trial-results) results
    print (word "Completed epsilon = " ee " with results: " trial-results)
  ]

  ;; Print final results
  print "Final Results:"
  foreach results [ r ->
    let ee item 0 r
    let trials item 1 r
    print (word "Epsilon: " ee " Results: " trials)
  ]

  ;; Calculate and print averages for each epsilon
  print "Averages:"
  foreach results [ r ->
    let ee item 0 r
    let trials item 1 r

    ;; Calculate averages across all metrics
    let avg-israeli-tanks-lost mean map [ t -> item 0 t ] trials
    let avg-egyptian-tanks-lost mean map [ t -> item 1 t ] trials
    let avg-israeli-inf-lost mean map [ t -> item 2 t ] trials
    let avg-egyptian-inf-lost mean map [ t -> item 3 t ] trials
    let avg-bh-israeli-pct mean map [ t -> item 4 t ] trials
    let avg-bh-egyptian-pct mean map [ t -> item 5 t ] trials
    let avg-cf-israeli-pct mean map [ t -> item 6 t ] trials
    let avg-cf-egyptian-pct mean map [ t -> item 7 t ] trials

    print (word "Epsilon: " ee)
    print (word "  Avg Israeli tanks lost: " avg-israeli-tanks-lost)
    print (word "  Avg Egyptian tanks lost: " avg-egyptian-tanks-lost)
    print (word "  Avg Israeli infantry lost: " avg-israeli-inf-lost)
    print (word "  Avg Egyptian infantry lost: " avg-egyptian-inf-lost)
    print (word "  Avg Bridgehead % Israeli: " avg-bh-israeli-pct)
    print (word "  Avg Bridgehead % Egyptian: " avg-bh-egyptian-pct)
    print (word "  Avg Chinese Farm % Israeli: " avg-cf-israeli-pct)
    print (word "  Avg Chinese Farm % Egyptian: " avg-cf-egyptian-pct)
  ]
end


to check-win-condition
  ;; Calculate control percentages
  let bh-total count bridgehead-zone
  let bh-israeli count bridgehead-zone with [captured-by = "israeli"]
  let bh-egyptian count bridgehead-zone with [captured-by = "egyptian"]
  let bh-israeli-pct bh-israeli / max (list 1 bh-total)  ;; Avoid division by zero
  let bh-egyptian-pct bh-egyptian / max (list 1 bh-total)

  let cf-total count chinese-farm-patches
  let cf-israeli count chinese-farm-patches with [captured-by = "israeli"]
  let cf-egyptian count chinese-farm-patches with [captured-by = "egyptian"]
  let cf-israeli-pct cf-israeli / max (list 1 cf-total)
  let cf-egyptian-pct cf-egyptian / max (list 1 cf-total)

  ;; Calculate unit strengths
  let israeli-tank-strength count israeli-tanks
  let egyptian-tank-strength count egyptian-tanks
  let israeli-inf-strength count infantry with [team = "israeli"]
  let egyptian-inf-strength count infantry with [team = "egyptian"]

  ;; Win Condition 1: Total elimination
  if israeli-tank-strength + israeli-inf-strength = 0 [
    show "Egyptian Decisive Victory: All Israeli forces eliminated!"
    stop
  ]
  if egyptian-tank-strength + egyptian-inf-strength = 0 [
    show "Israeli Decisive Victory: All Egyptian forces eliminated!"
    stop
  ]

  ;; Win Condition 2: Bridgehead dominance (after tick 50)
  if ticks > 200 [
    ;; Israeli Victory Conditions
    if bh-israeli-pct > 0.75 and cf-israeli-pct > 0.5 [
      show "Israeli Major Victory: Secured bridgehead and majority of Chinese Farm!"
      stop
    ]
    if bh-israeli-pct > 0.9 [
      show "Israeli Bridgehead Victory: Total bridgehead control achieved!"
      stop
    ]

    ;; Egyptian Victory Conditions
    if bh-egyptian-pct > 0.6 and cf-egyptian-pct > 0.4 [
      show "Egyptian Major Victory: Maintained bridgehead and significant farm control!"
      stop
    ]
    if bh-egyptian-pct > 0.75 and israeli-tank-strength < (0.3 * egyptian-tank-strength) [
      show "Egyptian Attrition Victory: Bridgehead control with enemy forces depleted!"
      stop
    ]
  ]

  ;; Win Condition 3: Stalemate/time-based (after tick 150)
  if ticks > 400 [
    if abs (bh-israeli-pct - bh-egyptian-pct) < 0.2 and abs (cf-israeli-pct - cf-egyptian-pct) < 0.3 [
      if bh-israeli-pct > bh-egyptian-pct [
        show "Marginal Israeli Victory: Stalemate but slight advantage in bridgehead!"
      ]
      if bh-egyptian-pct > bh-israeli-pct [
        show "Marginal Egyptian Victory: Stalemate but slight advantage in bridgehead!"
      ]
      if bh-israeli-pct = bh-egyptian-pct [
        show "Draw: Neither side achieved decisive advantage!"
      ]
      stop
    ]
  ]
end

to setup-fortified-lines
  ;; border-thickness is 3 patches.
  let border-thickness 3
  ;; The outer fortified square extends 3 patches beyond the strategic block.
  ;; For a strategic center at (cx,cy), the strategic block covers:
  ;;    x from (cx-1) to (cx+1) and y from (cy-1) to (cy+1)
  ;; The outer boundary will be:
  ;;    x from (cx - 1 - border-thickness) to (cx + 1 + border-thickness)
  ;;    y from (cy - 1 - border-thickness) to (cy + 1 + border-thickness)
  let strategic-centers [[210 320] [190 300] [240 325]]
  foreach strategic-centers [ sc ->
    let cx item 0 sc
    let cy item 1 sc
    let x-min (cx - 1 - border-thickness)  ; = cx - 4
    let x-max (cx + 1 + border-thickness)  ; = cx + 4
    let y-min (cy - 1 - border-thickness)  ; = cy - 4
    let y-max (cy + 1 + border-thickness)  ; = cy + 4
    ;; Fortify all patches in that square that are NOT in the inner strategic block.
    ask patches with [
      pxcor >= x-min and pxcor <= x-max and
      pycor >= y-min and pycor <= y-max and
      (pxcor < (cx - 2) or pxcor > (cx + 2) or pycor < (cy - 2) or pycor > (cy + 2))
    ] [
      if terrain-type = "chinese-farm" [
        set fortified? true
        set pcolor pink
      ]
    ]
  ]
end

to setup-mines
  ask patches with [ terrain-type = "chinese-farm" ] [
    if pycor < 310 and pxcor < 325 [
      if random-float 1 < 0.03 [  ;; 4% chance for patches below y=50
        set mine? true
        set pcolor red
      ]
    ]
  ]
end


to check-landmines
  ask turtles [
    if [mine?] of patch-here [
      ;; Turtle touches a mine: apply death penalty and kill the turtle.
      penalize-death
      ;; Remove the mine after triggering and reset the patch color.
      ask patch-here [
        set mine? false
        ;; Restore the patch color based on its terrain.
        if terrain-type = "chinese-farm" [ set pcolor green ]
        if terrain-type = "road" [ set pcolor gray ]
        if terrain-type = "desert-west" [ set pcolor yellow ]
        if is-strategic [ set pcolor violet ]
      ]
    ]
  ]
end
@#$#@#$#@
GRAPHICS-WINDOW
278
10
1310
1043
-1
-1
2.0
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
511
0
511
0
0
1
ticks
30.0

BUTTON
25
98
88
131
NIL
setup
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
25
145
88
178
NIL
go
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
24
204
224
354
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
"Israel" 1.0 0 -15637942 true "" "plot count turtles with [team = \"israeli\"]"
"Egyptian" 1.0 0 -13345367 true "" "plot count turtles with [team = \"egyptian\"]"

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
