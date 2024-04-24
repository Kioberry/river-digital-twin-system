extensions [table]

breed [ water a-water ]
breed [ flows flow ]
breed [ houses house]
breed [raindrops raindrop]
breed [ flags flag]
globals [
  infiltration-rate
  discharge-rate
  water-height
  water-id
  converted
  grad-table
  perm-table

  impondage
  water-spread-threshold
  sediment-color-flag
  warning-impondage
  downstream-threshold
  levelup-threshold
  escape-threshold

  ;evacuation speed
  remaining-rescue
  prev-remaining-rescue
  rescue-speed

  ;flood spreading speed
  prev-flood-area
  flood-area
  spread-speed

  ;impodage-rate
  prev-total-impondage
  impondage-growth-speed
  speed-sums
  interval-counts
  ticks-of-interest
  average-speeds

  total-impondage
  live-rainfall
  sinuosity-degree

  ;rain-imp-list
  ;eva-list
  imp-list
  ;remain-list
  spread-list
  flable

]

water-own [
  depth
  potential-energy
  source?
  drain?
  water-size
  creation-time
  sediment-amount
]

flows-own [
  speed
  age
  distance-traveled
]

patches-own [
  elevation
  water-level
  color-diff
  base-color
  colored-elevation
]

houses-own [
  level
  population
  evacuated
]

raindrops-own [
  age
]

;;;;;;;;;;;;;;;;;;;;
;; Initialization ;;
;;;;;;;;;;;;;;;;;;;;

to setup
  clear-all
  set water-height 10
  set impondage 0
  set water-spread-threshold 1000
  set warning-impondage 0
  set downstream-threshold 850
  set converted []
  set sediment-color-flag 0
  set levelup-threshold 5000
  set escape-threshold 1200
  set total-impondage 0
  set prev-total-impondage 0
  set impondage-growth-speed 0
  set live-rainfall 0
  ;;;;;;;;;;;;;;;;;;;;;;;
  set speed-sums [0 0 0]
  set interval-counts [0 0 0]
  set average-speeds []

  set prev-remaining-rescue 0
  set remaining-rescue 0
  set rescue-speed 0

  set prev-flood-area 0
  set flood-area 0
  set spread-speed 0

  ;set rain-imp-list []
  ;set eva-list []
  ;set imp-list []
  ;set remain-list []
  ;set spread-list []
  set flable 0

  create-terrain
  ask water with [ (sin (sinuosity * ycor) * amplitude) > xcor - (river-width / 2) and
  (sin (sinuosity * ycor) * amplitude) < xcor + (river-width / 2) and ycor = max-pycor]
  [ set source? true ]
  reset-ticks
end

to randomize
  update-sinuosity
  update-source-and-drains
  update-water
  update-flows
  ; Gradually lighten the land patches, to simulate the meander scars slowly fading over time
  ask patches with [shade-of? pcolor green] [if pcolor < green [
      set pcolor (pcolor + .004)

      set color-diff color-diff + .004
    ]
  ]
  tick
end

to create-terrain
  ask patches [
    set pcolor green
    set base-color green
    set color-diff 0
  ]
  ask patches [
    ; 判断该补丁是否在正弦曲线上
     if (sin (sinuosity * pycor) * amplitude) > pxcor - (river-width / 2) and
       (sin (sinuosity * pycor) * amplitude) < pxcor + (river-width / 2)
    [
      create-water-here
    ]
  ]
end


to create-houses-onland
  ; 三个距离档次的房子数量
  let houses-close 23
  let houses-mid 14
  let houses-far 14

  ; 创建靠近河流的房子
  create-houses-in-range houses-close 6 10
  ; 创建中等距离河流的房子
  create-houses-in-range houses-mid 10 30
  ; 创建远离河流的房子
  create-houses-in-range houses-far 30 70

  remove-close-houses

end

to create-houses-in-range [num-houses min-range max-range]
  repeat num-houses [
    ; 随机选择符合条件的地块
    let land-patch one-of patches with [
      pcolor = green and
      pycor >= min-pycor + 1 and pycor <= max-pycor - 1 and
      min-dist-water > min-range and
      min-dist-water <= max-range
    ]
    ; 如果找到符合条件的地块，则在该地块上创建房屋
    if land-patch != nobody [
      create-houses 1 [
        move-to land-patch
        set shape "house"
        set color white
        set size ((random 3) / 2) + 3  ; 在3、3.5、4之间随机选择一个大小
        set level 0
        set population (size - 2) * 1000
        set evacuated 0
      ]
    ]
  ]
end

to remove-close-houses
  ; 创建一个列表来存储需要删除的房屋
  let houses-to-remove []

  ; 检查每个房屋与其他房屋之间的距离
  ask houses [
    if any? other houses with [distance myself <= 3] [
      set houses-to-remove lput self houses-to-remove
    ]
  ]

  ; 删除所有过于接近的房屋
  foreach houses-to-remove [current-house ->
    ask current-house [ die ]
  ]
end



; 初始化Perlin噪声系统
to setup-perlin
  ; 定义8个可能的梯度向量（简化版）
  set grad-table [[1 1] [-1 1] [1 -1] [-1 -1] [1 0] [-1 0] [0 1] [0 -1]]

  ; 生成一个排列表
  set perm-table (n-values 512 [random 256])

  ; 确保排列表是重复两次的，避免边界问题
  set perm-table (sentence perm-table perm-table)
end


to-report lerp [a b t]
  report a + (b - a) * t
end

to-report perlin-noise [x y]
  let xi floor x
  let yi floor y

  let xf x - xi
  let yf y - yi

  let u fade xf
  let v fade yf

  ; 确保操作符两侧有空格
  let n00 gradient-dot-grid xi yi xf yf
  let n01 gradient-dot-grid xi (yi + 1) (xf) (yf - 1)
  let n10 gradient-dot-grid (xi + 1) yi (xf - 1) yf
  let n11 gradient-dot-grid (xi + 1) (yi + 1) (xf - 1) (yf - 1)

  ; 使用lerp函数进行插值计算
  let nx0 lerp n00 n10 u
  let nx1 lerp n01 n11 u
  let nxy lerp nx0 nx1 v

  report nxy
end

; 平滑曲线函数
to-report fade [t]
  report t * t * t * (t * (t * 6 - 15) + 10)
end

to-report gradient-dot-grid [xi yi x y]
  ; 修正mod的使用
  let grad-index (item (xi mod 256) perm-table + item (yi mod 256) perm-table) mod 256
  let grad-vector item (grad-index mod 8) grad-table
  report (item 0 grad-vector) * x + (item 1 grad-vector) * y
end

; 在设置高程之前，记录沉淀物颜色的变化量
to record-deposition-color
  ask patches [
    if shade-of? pcolor green [
      set color-diff pcolor - green  ; 假设pcolor是个数值
    ]
  ]
end

; 设置高程
to setup-elevation
  record-deposition-color
  setup-perlin
  let max-elevation 1000
  let min-elevation 200
  let elevation-range (max-elevation - min-elevation)
  let base-noise-factor 0.3  ; 基础噪声系数
  let additional-noise-factor 0.5  ; 额外噪声系数

  ask patches [
    let x (pxcor + (world-width / 2)) / world-width
    let y (pycor + (world-height / 2)) / world-height
    let base-elevation-incline ((pycor - min-pycor) / (world-height) * elevation-range) + min-elevation

    ; 调整噪声系数，使其在高程低的地方变化更明显
    let noise-factor base-noise-factor + ((world-height / 2 - abs pycor) / world-height) * additional-noise-factor
    let noise (perlin-noise x y - 0.5) * noise-factor * elevation-range

    let final-elevation base-elevation-incline + noise

    ; 随机性偏移
    let random-noise-factor 0.1  ; 随机噪声系数
    let random-noise (random-float 2 - 1) * random-noise-factor * elevation-range  ; 生成随机噪声
    let randomized-elevation final-elevation + random-noise

    set elevation randomized-elevation
    set colored-elevation final-elevation
  ]
  ;遍历所有河流区域方格
  ask patches with [pcolor = black] [
    if any? water-here [
      ; 如果有，将所有水代理的潜能能量相加，然后加上70设置为方格的高程
      set elevation (sum [potential-energy] of water-here)
    ]
  ]

  update-patches-color
  clear-all-plots
  reset-ticks
  set prev-remaining-rescue sum [population] of houses with [min-dist-water > 0 and min-dist-water <= 30 and evacuated = 0]
  set remaining-rescue sum [population] of houses with [min-dist-water > 0 and min-dist-water <= 30 and evacuated = 0]
  set prev-flood-area count patches with [pcolor = black]
  set flood-area count patches with [pcolor = black]
end


to update-patches-color
  ;; 计算颜色映射范围
  let max-final-elevation max [elevation] of patches
  let min-final-elevation min [elevation] of patches
  ;print max-final-elevation
  ;print min-final-elevation

  ;; 如果想要整体颜色更浅，可以减少减少color-min的调整
  let color-max max-final-elevation + 300  ; 为了减少白色区域加一些缓冲
  let color-min-adjustment ((color-max - min-final-elevation) / 3)  ; 更小的调整
  let color-min min-final-elevation - color-min-adjustment  ; 通过调整这个值来调整颜色

  ;; 根据计算的颜色映射范围更新地块颜色
  ask patches with [pcolor != black ][
    set pcolor scale-color green colored-elevation color-min color-max
  ]

  ask patches [
    set base-color scale-color green colored-elevation color-min color-max
    set sediment-color-flag 1
  ]

  ask patches [
    if color-diff != 0 [  ; 如果之前记录了颜色差异
      set pcolor pcolor + color-diff
    ]
  ]
end



to-report min-dist-water
  ; 报告当前补丁到最近河流的距离
  report min [distance myself] of patches with [pcolor = black]
end

to update-source-and-drains
  let target-x 0
  let max-y-water water with [ycor = max-pycor - 1]
  ifelse (count max-y-water > 0 )[
    ;计算这些water的x坐标的平均值
    let mean-x mean [pxcor] of max-y-water
    ; 四舍五入到最接近的整数，因为patch的坐标是整数
    set target-x round mean-x
  ][
    print "No water found at the specified y level."
  ]

  ; Initialize new flows from the source water tukes
  ask patch target-x (max-pycor - 1) [
    ask patches in-radius 1 [ create-water-here ]
    ask one-of patches in-radius 1 [ create-flow-here 3 ]
    ask flows in-radius 5 [
      set heading 180
      set speed max-flow-speed
    ]
  ]

  ; Update the drain water tiles along the bottom of the screen
  ask water with [ycor = min-pycor] [
    set drain? true
  ]

end

to update-water
  ask water [
    let neighboring-water (water-on neighbors)

    ; The farther a water tile is from a land patch - or the edge of the river - the deeper the river is.
    ; The maximum depth is 5, as in real life a river's depth is limited, and does not keep increasing infinitely the wider it gets.
    ifelse any? neighbors with [shade-of? pcolor green]
      [ set depth 1 ]
      [ set depth [depth + 1] of min-one-of neighboring-water [depth] ]


    if depth > 7 [ set depth 7 ]
    ; Update the flow gradient using each water's potential-energy property
    (ifelse
      source? [ set potential-energy  100 ]
      drain?  [ set potential-energy -100 ]
      [ if any? neighboring-water [set potential-energy mean [potential-energy] of neighboring-water] ]
    )
    ; Set color
    set color blue + 1 - (0.2 * depth)

    ; Deposition - Each tick, the amount of sediment settled on a water tile increases by one percent.
    ; If not enough flow passes through this water patch to wash away the sediment,
    ; it will turn into a land patch once reaching 100%
    ifelse impondage < water-spread-threshold [
      set sediment-amount (sediment-amount + 0.7)
    ][
      set sediment-amount (sediment-amount + 0.5)
    ]


    if sediment-amount >= 100 [
      ifelse sediment-color-flag = 0 [
        set pcolor green - 1.5
      ][
        set pcolor base-color - 1.5
      ]
      set color-diff  -1.5
      die
      set total-impondage total-impondage - 1
    ]

  ]
end

to update-flows
  ask flows [
    ifelse any? water-here [
      let this-water one-of water-here

      ; This serves to simulate the flowing water washing away part of the sediment that had settled on the riverbed at this patch.
      ; Thus, the sediment-amount on this water is decreased by 15 (or set to 0 if it is currently less than 15).
      ask this-water [
        if sediment-amount > 0 [
          ifelse sediment-amount >= 15 [set sediment-amount (sediment-amount - 15)] [ set sediment-amount 0 ]
        ]
      ]

      ; Because the angles at which the "flow gradient" force are applied to the flow turtle are important,
      ; we need a coarse grain size to achieve angles other than towards each of the 8 neighbors.
      let nearby-water (water in-radius 3) with [self != this-water]

      ; There cannot be any flow on a single patch of water
      if not any? nearby-water [die]

      ; This code takes the average position of the nearby water with the least potential energy,
      ; and accelerates the flow towards this average position with an acceleration of FLOW-ACCELERATION.
      let min-potential-energy min [potential-energy] of nearby-water
      let nearby-min-water (nearby-water with [potential-energy = min-potential-energy])
      let force-dir heading
      let force-x mean [xcor] of nearby-min-water
      let force-y mean [ycor] of nearby-min-water

      ; towardsxy returns an error if the x and y coords are the same as the agent.
      if (force-x != xcor or force-y != ycor) [ set force-dir towardsxy force-x force-y ]

      add-force (force-dir) flow-acceleration

      ; This simulates occasional random turbulence in the flow of the river
      if random 100 < 50 [ add-force (heading + random 12 - 6) flow-acceleration / 2 ]

      ; This simulates the fastest flow of a river being located at its center
      add-force (towards max-one-of nearby-water [depth]) river-center-acceleration

      ; This simulates the gravitational pull towards the center of the U-shaped river valley
      ; in which the river is situated in, which limits the amplitude of a river's meander
      if (abs xcor) >= 3 [ add-force (towardsxy 0 ycor) ((xcor ^ 2) * .005) ]

      ; This simulates the gravitational pull down the gradual downwards incline of the river valley in which the river is situated in
      add-force 180 downwards-incline-force

      ; Eroding - turning a land patch into a water patch upon flow impacting the land
      erode

      ; Move the flow forward an amount based on its speed and update its distance-traveled.
      ; If the speed is too strong and the flow would end up in a land patch, then only move forward a distance of .5
      ifelse (patch-ahead (.1 * speed) != nobody) and any? water-on patch-ahead (.1 * speed) [
        fd .1 * speed
        set distance-traveled (distance-traveled + (.1 * speed))
      ][
        fd .5
        set distance-traveled (distance-traveled + .5)
      ]

    ][ die ] ; Flow can only exist on water

    ; The river can be assumed to continue flowing further down beneath the world, but the flows modeled will die here.
    if (ycor < min-pycor) [ die ]

    ifelse show-flows? [ set hidden? false ] [ set hidden? true ]

  ]
  if count flows >= 1500 [ask flows [if random 100 < 30 [die]]]
end

to create-water-here
  if not any? water-here [
    set pcolor black
    set water-id water-id + 1 ;
    sprout-water 1 [
      set shape "square"
      set size 1.4
      set depth 0
      set color blue + 1
      set potential-energy 0
      set drain? false
      set source? false
      set water-size 1
      set creation-time water-id ; 设置创建时间为当前水ID
      set sediment-amount 0
    ]
  ]
end

to create-flow-here [ num ]
  sprout-flows num [
    set color blue + 1
    set color white
    set hidden? true
    set speed 0
    set age 0
  ]
end

to erode
  let this-water one-of water-here
  let following-patch (patch-ahead 1)
  if following-patch != nobody and not any? (water-on following-patch) [
      ask following-patch [
        create-water-here
        ask water-here [ set potential-energy ([potential-energy] of this-water) ]
      ]
    ; "Bounce" the flow back - a true deflection using angle of incidence against
    ; the normal would be ideal, but we simplfy here
    add-force (heading + 180) (speed + .1)
  ]
end

to add-force [ direction magnitude ]
  if speed <= 0 [ set heading direction ]

  let force-dx (sin direction) * magnitude
  let force-dy (cos direction) * magnitude
  let new-dx (dx * speed + force-dx)
  let new-dy (dy * speed + force-dy)

  ifelse new-dx = 0 and new-dy = 0
    [ set heading direction ]
    ; .001 is added/subtracted to prevent an atan 0 0 error
    [ set heading (atan (new-dx + .001) (new-dy - .001)) ]

  let new-speed (sqrt (new-dx ^ 2 + new-dy ^ 2))
  if new-speed > max-flow-speed [ set new-speed max-flow-speed ]

  set speed new-speed
end

;;;;;;;;;;;;;;;;;;;;
;; rainfall-flow  ;;
;;;;;;;;;;;;;;;;;;;;

to go
  go-rain
  ifelse warning? [
    update-warning
    evacuation
  ][
    escape
  ]
  evacuate-status
  update-my-plots
  data-outcome
  if impondage >= water-spread-threshold and flable = 0[
    print ticks
    set flable 1
  ]
  tick
end


to go-rain
  ;; 假设你已经有了一个明确区分河流和陆地的方法
  ;; 比如，河流的elevation设置为一个特定值，或者河流和陆地的pcolor不同
  let river-patches patches with [pcolor = black]  ;; 假设河流patches为黑色
  ;; 选择陆地patches，即那些不是河流的patches
  let land-patches patches with [pcolor != black]

  let total-patches (count river-patches) + (count land-patches)
  let raindrops-per-area (rainfall / 5)   ;; 假设雨量平均分配到两个区域

  ;; 在河流上生成雨滴
  repeat raindrops-per-area [
    if random 100 < 30 [
      ask one-of river-patches [
        sprout-raindrops 1 [
          set color blue + 4
          set color blue + 4
          set size 1.5
          set shape "circle"
          set age 0
        ]
      ]
    ]
  ]

  ;; 在陆地上生成雨滴
  repeat raindrops-per-area - 2 [
    if random 100 < 70 [
      ask one-of land-patches [
        sprout-raindrops 1 [
          set color blue + 4
          set size 1.5
          set shape "circle"
          set age 0
        ]
      ]
    ]
  ]

  set live-rainfall live-rainfall + 2 * raindrops-per-area - 2
  ;; 更新雨滴
  update-raindrops
end

to update-raindrops
  ask raindrops[
    ifelse any? water-here [
      ;添加落入河中的雨点信息到list
      set converted lput (list xcor ycor size) converted

      let current-age age
      ask patch-here [
        create-water-here
        let newest-water max-one-of water-here [creation-time]
        ask newest-water [
          set water-size (water-size * (20 - current-age) / 20)
          set impondage impondage + water-size
          set warning-impondage warning-impondage + sum ([water-size] of water-here)
          set total-impondage total-impondage +  sum ([water-size] of water-here)
        ]
        ]
      die
    ][
      update-ground ; 假设你已经有了一个处理陆地上雨滴的过程
    ]
  ]
  update-river
end

to update-ground
    ; 否则寻找最低的邻居并移动到那里
    let target min-one-of neighbors [elevation]
    ifelse [elevation] of target < [elevation] of patch-here [
      move-to target
    ][
      fade-away
    ]
    ; 增加雨滴的年龄
    set age age + 1

    ; 如果雨滴年龄达到10个tick，它消失
    if age >= 10 [ die ]
end

to update-river
  update-source-and-drains
  update-water
  update-rain-flows
  ; Gradually lighten the land patches, to simulate the meander scars slowly fading over time
  ask patches with [shade-of? pcolor green] [if color-diff < 0[
      set pcolor (pcolor + .004)
      ifelse color-diff < 0 [
        set color-diff (color-diff + .004)
      ][
        set color-diff 0
      ]
    ]
  ]
end

to update-rain-flows
  ask flows [
    ifelse any? water-here [
      ; 计算当前water的有效高度
      let this-water one-of water-here

      ; This serves to simulate the flowing water washing away part of the sediment that had settled on the riverbed at this patch.
      ; Thus, the sediment-amount on this water is decreased by 15 (or set to 0 if it is currently less than 15).
      let erosion-rate-level-1 15
      let erosion-rate-level-2 45

      ask this-water [
        if sediment-amount > 0 [
          ifelse sediment-amount >= erosion-rate-level-1 [set sediment-amount (sediment-amount - erosion-rate-level-1)] [ set sediment-amount 0 ]
          if impondage >= water-spread-threshold [
            ifelse sediment-amount >= erosion-rate-level-2 [set sediment-amount (sediment-amount - erosion-rate-level-2)] [ set sediment-amount 0 ]
          ]
        ]

      ]

      let valid-size sum [water-size] of water-here
      let current-effective-height elevation
          + (water-height * valid-size)

      ; 获取周围的水体patches
      let nearby-water (water in-radius 3) with [self != this-water]

      ; There cannot be any flow on a single patch of water
      if not any? nearby-water [die]

      ; 从周围的水体中找到有效高度最小的那个
      ; 从周围的水体patches中找到有效高度最小的那个
      let nearby-min-water min-one-of nearby-water [;[elevation] of patch-here
        [elevation] of patch-here + (water-height * sum [water-size] of water-here)
      ]

      ; 如果找到了符合条件的周围水体
      if nearby-min-water != nobody [
        ; 计算目标方向
        let force-dir heading
        let force-x [xcor] of nearby-min-water
        let force-y [ycor] of nearby-min-water
        ; towardsxy returns an error if the x and y coords are the same as the agent.
        if (force-x != xcor or force-y != ycor) [ set force-dir towardsxy force-x force-y ]

        ; 应用力，加速流动
        add-force force-dir flow-acceleration
        ; This simulates occasional random turbulence in the flow of the river
        if random 100 < 50 [ add-force (heading + random 12 - 6) flow-acceleration / 2 ]

        ; This simulates the fastest flow of a river being located at its center
        add-force (towards max-one-of nearby-water [depth]) river-center-acceleration

        ; This simulates the gravitational pull towards the center of the U-shaped river valley
        ; in which the river is situated in, which limits the amplitude of a river's meander
        if (abs xcor) >= 3 [ add-force (towardsxy 0 ycor) ((xcor ^ 2) * .005) ]

        ; This simulates the gravitational pull down the gradual downwards incline of the river valley in which the river is situated in
        add-force 180 downwards-incline-force

        rain-erode
        ;erode

        ; 如果速度较强，考虑增加前进的基础距离，使得水流能够更远距离移动
        ifelse (patch-ahead (.1 * speed) != nobody) and any? water-on patch-ahead (.1 * speed) [
          fd .1 * speed
          set distance-traveled (distance-traveled + (.1 * speed))
        ][
          fd (.5 + speed / 10) ; 根据速度动态调整前进距离
          set distance-traveled (distance-traveled + (.5 + speed / 10))
        ]
      ]
    ][ die ]
    ; The river can be assumed to continue flowing further down beneath the world, but the flows modeled will die here.
    if (ycor < min-pycor) [ die ]

    ifelse show-flows? [ set hidden? false ] [ set hidden? true ]
  ]
  if count flows >= 1500 [ask flows [if random 100 < 30 [die]]]
  raindrops-flows

end

to rain-erode
  if any? water-here [
    let this-water one-of water-here

    ;let current-effective-height elevation + (water-height * sum [water-size] of water-here)

    let following-patch patch-ahead 1
    if following-patch != nobody and not any? (water-on following-patch) [
      ask following-patch [
        create-water-here
        set warning-impondage warning-impondage + 1
        set total-impondage total-impondage + 1
        ask water-here [set potential-energy ([potential-energy] of this-water)]
      ]
      ; "Bounce" the flow back - a true deflection using angle of incidence against
      ; the normal would be ideal, but we simplfy here
      add-force (heading + 180) (speed + .1)
    ]


    if impondage > water-spread-threshold [
      ; 扩散逻辑
      if any? neighbors with [not any? water-here] [
        let target one-of neighbors with [not any? water-here]
        ask target [create-water-here]
         set warning-impondage warning-impondage + 1
        set total-impondage total-impondage + 1
      ]
    ]
  ]
end


;处理河流中的"雨滴"的流动
to raindrops-flows
  if not empty? converted [
    ;;;;;;转换flows形状;;;;;
    foreach converted [
      current-item ->
      let x item 0 current-item
      let y item 1 current-item
      let raindrop-size item 2 current-item
      let current-patch patch x y
      ask current-patch [
        let target-flow one-of flows-here with [shape != "circle" and not any? other flows-here with [shape = "circle"]]
        if target-flow != nobody [
          ask target-flow [
            set shape "circle"
            set size raindrop-size
            set color blue + 4
            set age 0
          ]
        ]
      ]
    ]


  ]

  ;;;;检查"raindrop flows"的更新;;;;;;;;;
  ask flows [
    if color = blue + 4 [  ; 假设改变后的颜色是黄色
      set age age + 1
      set size size - 0.1
      if age >= 10 [
        set shape "default"  ; 恢复到原始形状
        set size 1  ; 恢复到原始大小
        set color white  ; 恢复到原始颜色
        set age 0  ; 重置age
      ]
    ]
  ]

  set converted []  ; 清空列表以便下一次更新
end

to fade-away
  ; 雨滴逐渐变淡表示正在渗透
  set size size - 0.1
end


to update-warning
  ask houses with [evacuated = 0][
    let isflag 0
    ; 首先为每个房子设置预警等级
    set-warning-level nobody

    ; 获取当前房子的预警等级
    let my-level level
    let nearest-houses min-dist-houses

    ; 对于最近的两个房子，如果它们的预警等级低于当前房子的等级减1，则提升它们的预警等级
    foreach nearest-houses [
      neighbor -> ask neighbor [
        if ([level] of neighbor < my-level - 1) [
          set-warning-level (my-level - 1)
          set isflag 1
        ]
      ]
    ]

    if (isflag = 1)[
      ; 创建或确认与最近房子的连接
      foreach nearest-houses [
        neighbor ->
        if not any? links with [end1 = neighbor or end2 = neighbor] [
          ; 如果没有连接，则创建一个新连接
          create-link-with neighbor [
            set color gray + 3 ; 设置连接的颜色为灰色
            set thickness 0.5  ; 设置连接的粗细
          ]
        ]
      ]
    ]
  ]
  update-impondage
  levelup-warning
end

to-report min-dist-houses
  let current-house self
  let sorted-houses sort-by [[a b] -> distance a < distance b] houses with [self != current-house and evacuated = 0 and (pxcor * [pxcor] of myself) >= 0
  and min-dist-water <= 30]
  let nearest-houses []
  ; 如果排序后的房子数量少于 2，则将所有房子都添加到最近邻居列表中
  ifelse length sorted-houses < 2 [
    set nearest-houses sorted-houses
  ] [
    ; 否则，只选择前两个房子作为最近的邻居
    set nearest-houses sublist sorted-houses 0 2
  ]
  report nearest-houses
end

;;;;;;;;;;;;;;;;;;;
;; river-warning ;;
;;;;;;;;;;;;;;;;;;;

to set-warning-level [new-level]
  ; 如果没有指定新级别，则根据与河流的距离确定级别
  ifelse not is-number? new-level [
    if (min-dist-water <= 4) [
      set level 3  ; 红色预警
      set color (list 255 69 0)
    ]
    if (min-dist-water > 4 and min-dist-water <= 5 and color != (list 255 69 0)) [
      set level 2  ; 橙色预警
      set color (list 255 165 0)
    ]
    if (min-dist-water > 5 and min-dist-water <= 6 and color != (list 255 165 0) and color != (list 255 69 0)) [
      set level 1  ; 黄色预警
      set color yellow
    ]
    ; 如果距离大于6，则保持默认颜色，无需设置颜色和级别
  ] [
    set level new-level
    ; 根据新级别设置颜色
    if (new-level = 3) [ set color (list 255 69 0) ]
    if (new-level = 2) [ set color (list 255 165 0) ]
    if (new-level = 1) [ set color yellow ]
    if (new-level = 0) [ set color white ]
  ]
end

to update-impondage
  if (ticks mod 40 = 0)[
    if warning-impondage >= downstream-threshold [
      propagate-warning
    ]

    set warning-impondage 0
  ]

end

to propagate-warning
  ; 只选取预警等级大于等于1的房屋，并按照 ycor 对这些房屋进行排序
  let down-houses sort-by [[a b] -> [pycor] of a > [pycor] of b] (houses with [level >= 1 and evacuated = 0])
  foreach down-houses [
    down-house ->
    ask down-house [
      let current-house self
      let nearest-downstream-house min-one-of (houses with [pycor < [pycor] of myself and (pxcor * [pxcor] of myself) >= 0 and evacuated = 0]) [distance myself]
      if (nearest-downstream-house != nobody and [level] of nearest-downstream-house < [level] of current-house) [
        ask nearest-downstream-house [
          set-warning-level [level] of current-house
        ]
        if not link-neighbor? nearest-downstream-house [
          create-link-with nearest-downstream-house [
            set color gray + 3 ; 设置连接的颜色为灰色
            set thickness 0.5  ; 设置连接的粗细
          ]
        ]
      ]
    ]
  ]

  ; 检查周围存在level为0的房子，并且在radius 5以内
  let leveled-houses houses with [level >= 1 and evacuated = 0]
  ask leveled-houses [
    let current-house self
    let nearby-houses-no-warning houses in-radius 6 with [level = 0 and evacuated = 0]
    if any? nearby-houses-no-warning [
      ask nearby-houses-no-warning [
        set level 0.5
        set color (list 173 216 230)  ; 设置为浅蓝色的RGB值
        if not link-neighbor? current-house [
          create-link-with current-house [
            set color blue  ; 设置连接的颜色为蓝色
            set thickness 0.5  ; 设置连接的粗细
          ]
        ]
      ]
    ]
  ]
end

to levelup-warning
  if impondage >= levelup-threshold [
    setup-peripheral-link
  ]
end

to setup-peripheral-link
  ; 分别为左岸和右岸的符合条件的房屋创建链路
  let target-houses houses with [min-dist-water > 10 and min-dist-water <= 30 and level = 0 and evacuated = 0]
  ask target-houses [
    set level 0.5
    set color (list 173 216 230)  ; 设置为浅蓝色的RGB值
  ]
  let peri-houses sort-by [[a b] -> [pycor] of a > [pycor] of b] (target-houses)
  foreach peri-houses [
    peri-house ->
    ask peri-house [
      let nearest-peri-house min-one-of (houses with [pycor < [pycor] of myself and (pxcor * [pxcor] of myself) >= 0 and evacuated = 0]) [distance myself]
      if nearest-peri-house != nobody [
        if not link-neighbor? nearest-peri-house [
          create-link-with nearest-peri-house [
            set color gray + 3 ; 设置连接的颜色为灰色
            set thickness 0.5  ; 设置连接的粗细
          ]
        ]
      ]
    ]
  ]
end

;;;;;;;;;;;;;;;;
;; evacuation ;;
;;;;;;;;;;;;;;;;

to evacuation
  let deductions [0 5 10 20]

  ask houses with [level >= 0.5 and evacuated = 0][
    ifelse level = 0.5 [
      ifelse population >= 2 [set population population - 2] [set population 0]
    ][
      let current-level level
      let deduction item current-level deductions
      ifelse population >= deduction [set population population - deduction][set population 0]
    ]
  ]
end

to escape
  if impondage >= escape-threshold [
    let eligible-houses-1 houses with [level = 0 and min-dist-water > 0 and min-dist-water <= 10]
    let eligible-houses-2 houses with [level = 0 and min-dist-water > 10 and min-dist-water <= 30]
    if random 100 < 80 [
      ask  eligible-houses-1 [ifelse population >= 5 [set population population - 5] [set population 0]]
    ]

    if random 100 < 40[
      ask eligible-houses-2 [ifelse population >= 3 [set population population - 3] [set population 0]]
    ]
  ]
end

to evacuate-status
  ask houses [
    if population <= 0 and evacuated = 0 [
      set evacuated 1
      set-warning-level (0)
      ask patch-here [
        if not any? flags-here [
          sprout-flags 1 [
            set color (list 138 43 226)
            set shape "flag"
            set size 4
          ]
        ]
      ]
    ]
  ]
end


;;;;;;;;;;;
;; plots ;;
;;;;;;;;;;;

to update-my-plots
  update-rescue
  update-spread-speed
  update-impondage-rate
  update-level-plot
  update-sinuosity
  set prev-total-impondage total-impondage
end

to update-rescue
  ;; 计算当前tick的剩余待救援人数
  let current-remaining-rescue sum [population] of houses with [min-dist-water > 0 and min-dist-water <= 30 and evacuated = 0]

  ;; 更新救援速度
  set rescue-speed prev-remaining-rescue - current-remaining-rescue
  if rescue-speed < 0 [
    set rescue-speed 0
  ]

  ;; 更新剩余待救援人数和前一个tick的剩余待救援人数
  set prev-remaining-rescue current-remaining-rescue
  set remaining-rescue current-remaining-rescue
end

to update-spread-speed
  let current-flood-area count patches with [pcolor = black]  ; 统计黑色patches数量
  set spread-speed current-flood-area - prev-flood-area
  set prev-flood-area current-flood-area
  set flood-area current-flood-area
end

to update-impondage-rate
  ; 假设您在这里或其他地方计算了 total-impondage
  set impondage-growth-speed total-impondage - prev-total-impondage
  ; 为下一次tick保存当前的总水量
  set prev-total-impondage total-impondage
end

to update-level-plot
  set-current-plot "Level Distribution"
  clear-plot
  ; 定义所有可能的level值
  let all_levels [0 0.5 1 2 3]
  let counts table:counts [ level ] of houses
  ; 设置X轴范围以覆盖所有可能的level值，考虑到共有5种level，索引从0到4
  set-plot-x-range 0 4
  let step 0.05 ; 用于绘制条形的步长

  ; 遍历所有可能的level值，而不是仅仅基于当前的counts
  (foreach all_levels (range length all_levels) [ [s i] ->
    ; 使用table:get检查counts中是否有s这个level的记录，没有则默认为0
    let y ifelse-value (table:has-key? counts s) [table:get counts s][0]
    let c hsb (i * 360 / length all_levels) 50 75
    ; 为每个level创建临时绘图笔，使用level值作为标识
    create-temporary-plot-pen (word "level-" s)
    set-plot-pen-mode 1 ; 设置为条形模式
    set-plot-pen-color c
    ; 绘制条形，由于可能y为0（该level无houses），使用if判断避免画空条形
    if y > 0 [foreach (range 0 y step) [ _y -> plotxy i _y ]]
    ; 在条形顶部绘制一条线以增强可读性，如果y大于0
    if y > 0 [
      set-plot-pen-color black
      plotxy i y
    ]
    ; 重置颜色以正确显示图例
    set-plot-pen-color c
  ])
end

to update-sinuosity
  let bottom-row-flows (flows with [ycor <= min-pycor + 1])
  if any? bottom-row-flows [
    let min-flow min-one-of bottom-row-flows [ distance-traveled ]
    let river-length [distance-traveled] of min-flow
    let shortest-dist [distancexy 0 max-pycor] of min-flow
    let new-sinuosity river-length / shortest-dist
    if (sinuosity-degree = 0) or (new-sinuosity < (sinuosity-degree + .5)) [ set sinuosity-degree new-sinuosity ]
  ]
end


;;;;;;;;;;;;;
;; results ;;
;;;;;;;;;;;;;



to data-outcome
 ;if ticks = 100 or ticks = 200 or ticks = 500 or ticks = 1000[
    ;set spread-list lput (list live-rainfall spread-speed) spread-list
    ;set imp-list lput total-impondage imp-list
;]


  ; 在模拟结束时打印结果
  if ticks = 10 [
    print (word "rainfall: " rainfall)
    ;print (word "live-rainfall, spread-speed: " spread-list)
    ;print (word "impondage: " imp-list)
  ]
end

; 累积速度和计数
to accumulate-speed [index]
  set speed-sums replace-item index speed-sums (item index speed-sums + impondage-growth-speed)
  set interval-counts replace-item index interval-counts (item index interval-counts + 1)
end

; 计算平均速度并重置
to calculate-average-speed [index]
  let avg-speed (item index speed-sums) / (item index interval-counts)
  set average-speeds lput avg-speed average-speeds
  set speed-sums replace-item index speed-sums 0  ; 重置速度总和
  set interval-counts replace-item index interval-counts 0  ; 重置计数
end
@#$#@#$#@
GRAPHICS-WINDOW
515
47
1295
552
-1
-1
3.845
1
10
1
1
1
0
0
0
1
-100
100
-64
64
0
0
1
ticks
30.0

BUTTON
18
20
84
53
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
89
20
186
53
NIL
randomize
T
1
T
OBSERVER
NIL
NIL
NIL
NIL
0

SLIDER
18
130
148
163
river-width
river-width
2
15
7.0
1
1
NIL
HORIZONTAL

SLIDER
153
131
314
164
sinuosity
sinuosity
4
12
8.5
.5
1
NIL
HORIZONTAL

SLIDER
316
131
477
164
amplitude
amplitude
1
10
6.5
.5
1
NIL
HORIZONTAL

SLIDER
17
197
161
230
max-flow-speed
max-flow-speed
20
30
26.6
.1
1
NIL
HORIZONTAL

SLIDER
168
197
312
230
flow-acceleration
flow-acceleration
0
25
8.3
.1
1
NIL
HORIZONTAL

SLIDER
18
242
192
275
river-center-acceleration
river-center-acceleration
1
20
11.0
1
1
NIL
HORIZONTAL

SLIDER
200
242
383
275
downwards-incline-force
downwards-incline-force
0
1
0.49
.01
1
NIL
HORIZONTAL

BUTTON
331
60
394
93
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
0

BUTTON
195
60
323
93
NIL
setup-elevation
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

SLIDER
18
308
190
341
rainfall
rainfall
20
400
300.0
1
1
NIL
HORIZONTAL

TEXTBOX
19
106
169
124
River shape settings
12
0.0
1

TEXTBOX
19
177
131
195
Flows settings
12
0.0
1

SWITCH
320
197
452
230
show-flows?
show-flows?
0
1
-1000

BUTTON
17
60
188
93
NIL
create-houses-onland
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

TEXTBOX
20
289
170
307
Rrainning settings
12
0.0
1

SWITCH
198
308
310
341
warning?
warning?
0
1
-1000

PLOT
13
348
272
553
Rescuing speed
Time (ticks)
rescure speed
0.0
10.0
0.0
200.0
true
true
"" ""
PENS
"speed" 1.0 0 -10899396 true "" "plot rescue-speed"
"pen-1" 1.0 0 -7500403 true "" "plot 0"

PLOT
282
349
499
553
Impoundage
Time(ticks)
Total-impoundage
0.0
10.0
0.0
20000.0
true
true
"" ""
PENS
"default" 1.0 0 -14070903 true "" "plot total-impondage"
"base" 1.0 0 -4539718 true "" "plot 50 * ticks"

PLOT
515
562
790
743
Level Distribution
warning level
number of houses
0.0
3.0
0.0
30.0
true
true
"" ""
PENS
"pen-0" 1.0 0 -408670 true "" ""

MONITOR
318
295
375
340
flows
count flows
2
1
11

PLOT
802
563
1056
743
Rainfall-sinuosity
live-rainfall
sinuosity
0.0
100.0
0.0
2.0
true
true
"" ""
PENS
"default" 1.0 0 -14835848 true "" "plot sinuosity-degree"
"base" 1.0 0 -612749 true "" "plot 1"

PLOT
1065
563
1302
743
Flood spreading
rainfall
spread speed
0.0
100.0
0.0
10.0
true
true
"" ""
PENS
"speed" 1.0 0 -11033397 true "" "plotxy live-rainfall spread-speed"
"pen-1" 1.0 0 -7500403 true "" "plotxy live-rainfall 0"

PLOT
14
561
271
744
Remaining rescued people
Time(ticks)
remaining rescue
0.0
10.0
0.0
40000.0
true
true
"" ""
PENS
"people" 1.0 0 -6917194 true "" "plot remaining-rescue"

PLOT
282
561
499
744
Impoundage rate
Time(ticks)
Impoundage growth
0.0
10.0
0.0
5.0
true
true
"" ""
PENS
"rate" 1.0 0 -13791810 true "" "plot impondage-growth-speed"

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
