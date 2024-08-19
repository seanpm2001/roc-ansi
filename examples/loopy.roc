app [main] {
    cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.13.0/nW9yMRtZuCYf1Oa9vbE5XoirMwzLbtoSgv7NGhUlqYA.tar.br",
    ansi: "../package/main.roc",
}

import cli.Stdout
import cli.Stdin
import cli.Tty
import cli.Task exposing [Task]
import cli.Http
import ansi.Core
import ansi.Draw

Model : {
    cursor : Draw.Position,
    screen: Draw.ScreenSize,
    virtual: Draw.VirtualScreen,
}

init : Model
init = {
    cursor: { row: 3, col: 3 },
    screen: {width:0, height:0},
    virtual: Draw.empty,
}

render : Model -> List Draw.DrawFn
render = \model ->
    [
        Draw.pixel { row: 0, col: 0 } { char: "A" },
        Draw.pixel { row: 10, col: 10 } { char: "e" },
        Draw.pixel { row: 20, col: 20 } { char: "i" },
        Draw.pixel { row: 30, col: 30 } { char: "o" },
        Draw.pixel { row: 40, col: 40 } { char: "u" },
        Draw.pixel { row: 0, col: model.screen.width } { char: "B" },
        Draw.pixel { row: model.screen.height, col: 0  } { char: "C" },
        Draw.pixel { row: model.screen.height, col: model.screen.width } { char: "D" },
        Draw.pixel model.cursor { char: "X" },
        #Draw.box { r : 0, c : 0, w : size.width, h : size.height, fg : Standard Blue, bg: Standard White },
    ]

main =
    Tty.enableRawMode!
    _ = Task.loop! init runUILoop
    Tty.disableRawMode!
    Stdout.write! (Core.toStr Reset)

    Stdout.line "Exiting..."

runUILoop : Model -> Task.Task [Step Model, Done Model] _
runUILoop = \prevModel ->

    screen = getTerminalSize!

    modelWithScreen = { prevModel & screen }

    _ =
        { Http.defaultRequest &
            url: "http://127.0.0.1:8000",
            body:
                """
                CURSOR: $(Inspect.toStr modelWithScreen.cursor)
                SCREEN: $(Inspect.toStr modelWithScreen.screen)
                """|> Str.toUtf8 ,
        }
        |> Http.send!

    (output, newVirtualScreen) = Draw.draw prevModel.virtual (Draw.render screen (render modelWithScreen))

    modelWithVirtualScreen = { modelWithScreen & virtual: newVirtualScreen }

    # note this is 1-based -- let's make a helper so people don't get caught out
    #Stdout.write! (Core.toStr (Control (Erase (Display All))))
    Stdout.write! (Core.toStr (Control (Cursor (Abs { row: 1, col: 1 }))))
    Stdout.write! output

    # log the output to an echo server... to help debug things
    # escape the 'ESC' character so it doesn't mess up things when displayed in a terminal
    _ =
        { Http.defaultRequest &
            url: "http://127.0.0.1:8000",
            body: output |> Str.replaceEach "\u(001b)" "ESC" |> Str.toUtf8 ,
        }
        |> Http.send!

    # Get user input
    input = Stdin.bytes |> Task.map! Core.parseRawStdin

    # Parse user input into a command
    command =
        when (input, modelWithVirtualScreen) is
            (Arrow Up, _) -> MoveCursor Up
            (Arrow Down, _) -> MoveCursor Down
            (Arrow Left, _) -> MoveCursor Left
            (Arrow Right, _) -> MoveCursor Right
            #(Lower D, _) -> ToggleDebug
            #(Action Enter, HomePage) -> UserToggledScreen
            #(Action Enter, ConfirmPage s) -> UserWantToDoSomthing s
            #(Action Escape, ConfirmPage _) -> UserToggledScreen
            #(Action Escape, _) -> Exit
            (Ctrl C, _) -> Exit
            #(Unsupported _, _) -> Nothing
            (_, _) -> Nothing

    # Action command
    when command is
        Nothing -> Task.ok (Step modelWithVirtualScreen)
        Exit -> Task.ok (Done modelWithVirtualScreen)
        MoveCursor direction -> Task.ok (Step (Core.updateCursor modelWithVirtualScreen direction))

getTerminalSize : Task.Task Core.ScreenSize _
getTerminalSize =

    # Move the cursor to bottom right corner of terminal
    [Cursor (Abs { row: 999, col: 999 }), Cursor (Position (Get))]
    |> List.map Control
    |> List.map Core.toStr
    |> Str.joinWith ""
    |> Stdout.write!

    # Read the cursor position
    Stdin.bytes
    |> Task.map Core.parseCursor
    |> Task.map! \{ row, col } -> { width: col, height: row }
