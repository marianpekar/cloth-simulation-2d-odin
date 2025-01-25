package main 

import rl "vendor:raylib"

Point :: struct {
     pos: rl.Vector2,
     prevPos: rl.Vector2,
     initPos: rl.Vector2,
     isPinned: bool,
     isSelected: bool
}

Stick :: struct {
    p0: ^Point,
    p1: ^Point,
    isTeared: bool
}

Cloth :: struct {
    points: [dynamic]^Point,
    sticks: [dynamic]^Stick
}

main :: proc() {
    rl.InitWindow(0, 0, "Cloth Simulation 2D")
    rl.ToggleBorderlessWindowed()
    screenWidth := rl.GetScreenWidth()
    screenHeight := rl.GetScreenHeight()
    rl.SetTargetFPS(60)

    // Cloth
    clothWidth :: 150
    clothHeight :: 75
    clothSpacing :: 10
    startX := (screenWidth - (clothWidth * clothSpacing)) / 2
    startY := screenHeight / 12
    cloth := MakeCloth(clothWidth, clothHeight, clothSpacing, startX, startY)

    // Physics
    drag :: f32(0.005)
    gravity :: rl.Vector2{0, 980}
    elasticity :: f32(100.0)

    // Update Loop
    fixedDeltaTime :: f32(1.0 / 300)
    accumulator: f32 = 0.0

    // Interaction
    cursorSize: f32 = 30.0
    
    for !rl.WindowShouldClose() { 
        HandleMouseInteraction(&cloth, &cursorSize)

        accumulator += rl.GetFrameTime()
        for accumulator >= fixedDeltaTime {
            UpdateCloth(&cloth, fixedDeltaTime, clothSpacing, drag, gravity, elasticity)
            accumulator -= fixedDeltaTime            
        }

        rl.BeginDrawing()
        rl.ClearBackground({33, 40, 48, 255})
        DrawCloth(&cloth, clothSpacing, elasticity)
        rl.EndDrawing()
    }

    rl.CloseWindow()
}

MakeCloth :: proc(width, height, spacing, startX, startY: i32) -> Cloth {
    cloth: Cloth

    for y := i32(0); y <= height; y += 1 {
        for x := i32(0); x <= width; x += 1 {
            point := new(Point)
            point.initPos = { f32(startX + x * spacing), f32(startY + y * spacing) }
            point.pos = point.initPos
            point.prevPos = point.initPos
            point.isPinned = y == 0
            append(&cloth.points, point)

            if x != 0 {
                stick := new(Stick)
                stick.p0 = cloth.points[len(cloth.points) - 2]
                stick.p1 = cloth.points[len(cloth.points) - 1]
                append(&cloth.sticks, stick)
            }

            if y != 0 {
                stick := new(Stick)
                stick.p0 = cloth.points[(y - 1) * (width + 1) + x]
                stick.p1 = cloth.points[y * (width + 1) + x]
                append(&cloth.sticks, stick)
            }
        }
    }

    return cloth
}

UpdateCloth :: proc(cloth: ^Cloth, deltaTime: f32, spacing: i32, drag: f32, acceleration: rl.Vector2, elasticity: f32) {
    for &point in cloth.points {
        UpdatePoint(point, deltaTime, spacing, drag, acceleration)
    }
    
    for &stick in cloth.sticks {
        UpdateStick(stick, spacing, elasticity)
    }
    
    UpdatePoint :: proc(point: ^Point, deltaTime: f32, spacing: i32, drag: f32, acceleration: rl.Vector2) {
        if point.isPinned {
            point.pos = point.initPos
            return
        }
    
        currentPos := point.pos
        point.pos += (point.pos - point.prevPos) * (1.0 - drag) + acceleration * deltaTime * deltaTime
        point.prevPos = currentPos
    }
    
    UpdateStick :: proc(stick: ^Stick, spacing: i32, elasticity: f32) {
        delta := stick.p1.pos - stick.p0.pos
        distance := rl.Vector2Length(delta)
    
        if distance > elasticity {
            stick.isTeared = true
        }
    
        correction: rl.Vector2 = delta * ((distance - f32(spacing)) / distance * 0.5) * 0.5
    
        if !stick.p0.isPinned && !stick.isTeared {
            stick.p0.pos += correction
        }
    
        if !stick.p1.isPinned && !stick.isTeared  {
            stick.p1.pos -= correction
        }
    }
}

DrawCloth :: proc(cloth: ^Cloth, spacing: int, elasticity: f32) {
    for &stick in cloth.sticks {
        DrawStick(stick, spacing, elasticity)
    }

    DrawStick :: proc(stick: ^Stick, spacing: int, elasticity: f32) {
        if (stick.isTeared) {
            return
        }
        
        distance := rl.Vector2Distance(stick.p0.pos, stick.p1.pos)
        color := stick.p0.isSelected || stick.p1.isSelected ? rl.BLUE : GetColorFromTension(distance, elasticity, spacing)
        rl.DrawLineV(stick.p0.pos, stick.p1.pos, color)
    }
}

GetColorFromTension :: proc(distance: f32, elasticity: f32, spacing: int) -> rl.Color {
    if distance <= f32(spacing) {
        return {
             44,
            222,
            130,
            255
        } // Green
    } else if distance <= f32(spacing) * 1.33 {
        t := (distance - f32(spacing)) / (f32(spacing) * 0.33)
        return {
            Lerp(44,  255, t),
            Lerp(222, 255, t),
            Lerp(130,   0, t),
            255
        } // Gradual transition to yellow
    } else {
        t := (distance - f32(spacing) * 1.33) / (elasticity - f32(spacing) * 1.33)
        return {
            Lerp(255, 222, t),
            Lerp(255,  44, t),
            Lerp(0,    44, t),
            255
        }  // Gradual transition to red
    }

    Lerp :: proc(a: f32, b: f32, t: f32) -> u8 {
        return u8(a + ((b - a) * t))
    }
}

HandleMouseInteraction :: proc(cloth: ^Cloth, cursorSize: ^f32) {
    SetCursorSize(cursorSize)
    InteractWithPoints(cloth, cursorSize)

    SetCursorSize :: proc(cursorSize: ^f32) {
        stepSize :: 5
        if rl.GetMouseWheelMove() > 0 {
            cursorSize^ += stepSize 
        } else if rl.GetMouseWheelMove() < 0 && !(cursorSize^ <= stepSize) {
            cursorSize^ -= stepSize
        }
    }

    InteractWithPoints :: proc(cloth: ^Cloth, cursorSize: ^f32) {
        @(static)prevMousePos : rl.Vector2
    
        mousePos   := rl.GetMousePosition()
        maxDelta   := rl.Vector2(100)
        mouseDelta := rl.Vector2Clamp(mousePos - prevMousePos, rl.Vector2(0), maxDelta)
    
        for &point in cloth.points {
            distance := rl.Vector2Distance(mousePos, point.pos)
            if distance < cursorSize^ {
    
                if rl.IsMouseButtonDown(.LEFT) {
                    // Drag selected points
                    point.prevPos = point.prevPos + mouseDelta
                    point.pos = point.pos + mouseDelta
                }
    
                point.isSelected = true
            }
            else {
                point.isSelected = false
            }
        }
    
        prevMousePos = mousePos 
    }
}