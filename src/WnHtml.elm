module WnHtml 
    (  NodeType( .. ) -- hide Root?
    , RootDef
    , RectDef
    , TextDef
    , Node
    , Children( .. )
    , makeScene
    , Scene
    , render
    , Extent( .. )
    , Align( .. )
     ) where

import Graphics.Element exposing ( .. )
import Graphics.Collage exposing ( .. )
import Text as CText exposing ( .. )
import Color exposing ( .. )
import Window
import List.Extra exposing ( .. )

type Either a b
    = Left a
        | Right b 

type NodeType = Root RootDef
    | Rect RectDef
    | Text TextDef

type alias RootDef =
    { 
    }

type alias RectDef =
    { background : Color
    }

type alias TextDef =
    { text : String
    }

canHaveChildren : NodeType -> Bool
canHaveChildren t = case t of
   Root _ -> True
   Rect _ -> True
   Text _ -> False

type alias NodeID = Int

type alias Node = 
    { nodeType : NodeType
    , extents : Extents
    , id : NodeID
    , children : Children
    }

-- Recursive type ( https://github.com/elm-lang/elm-compiler/blob/master/hints/recursive-alias.md )
type Children = Flow Direction ( List Node )
    | Empty

overlay cs = Flow outward cs

rootNode : Node
rootNode = 
    { nodeType = Root {}
    , extents = ( Fill 1.0, Fill 1.0 )
    , id = 0
    , children = overlay []
    }

type alias Scene = Node

-- size of form cannot be queried easily, enhance the rendered form with it
type alias Render = Either Element ( Form, Sizes )

makeScene : List Node -> Scene
makeScene nodes = { rootNode | children = overlay nodes }


-- SCENE RENDER

render : Scene -> Signal Element
render scene = Signal.map ( renderScene scene ) Window.dimensions

renderScene : Scene -> ISizes -> Element
renderScene scene size = renderNodes size ( fst size |> Just, snd size |> Just ) 
    scene |> renderToElement

renderNodes : ISizes -> ( Maybe ISize, Maybe ISize ) -> Node -> Render
renderNodes sceneSize ( parentW, parentH ) node = 
    let getSize extent parentSize =  case fst node.extents of
           Fix w -> Just ( ceiling w )
           Fit -> Nothing
           Fill ratio -> parentW
        size = ( getSize ( fst node.extents ) parentW
               , getSize ( snd node.extents ) parentH )
        ( children, childrenSize ) = renderChildren sceneSize size node.children
        this = renderNode sceneSize ( parentW, parentH ) childrenSize node 
            |> renderToElement
    in flow outward [ this, renderToElement children ] |> Left

renderChildren : ISizes -> ( Maybe ISize, Maybe ISize ) -> Children 
   -> ( Render, Maybe ISizes )
renderChildren sceneSize parentSize children = 
    let compose dir cs = case cs of
            [one] -> one
            many -> List.map renderToElement many |> flow dir |> Left
    in case children of
        Flow dir cs -> 
            let render = List.map ( renderNodes sceneSize parentSize ) cs 
                |> compose dir
            in ( render, sizeOfRender render |> Just )
        Empty -> ( Left Graphics.Element.empty, Nothing )

sizeOfRender : Render -> ISizes
sizeOfRender render = case render of
    Left e -> sizeOf e
    Right ( f, s ) -> toInt2 s

maxSizes : List ISizes -> ISizes
maxSizes sizes = 
    let max which = List.map which sizes |> List.maximum |> Maybe.withDefault 0
    in ( max fst, max snd )

renderToElement : Render -> Element
renderToElement render = case render of
    Left element -> element
    Right ( form, ( width, height ) ) -> 
        collage ( ceiling width ) ( ceiling height ) [form]

renderToForm : Render -> Form
renderToForm render = case render of
    Left element -> toForm element
    Right ( form, _ ) -> form

renderNode : ISizes -> ( Maybe ISize, Maybe ISize ) -> Maybe ISizes -> Node 
   -> Render
renderNode sceneSize ( parentW, parentH ) childrenSizes node = 
    let getSize extent parentSize childrenSize = 
            Maybe.withDefault 0.0 ( case extent of
                Fix w -> Just w
                Fit -> Maybe.map ( toFloat ) childrenSize
                Fill ratio -> Maybe.map ( toFloat >> ( * ) ratio ) parentSize )
        ( width, height ) = ( getSize ( fst node.extents ) parentW 
                                ( Maybe.map fst childrenSizes )
                            , getSize ( snd node.extents ) parentH 
                                ( Maybe.map snd childrenSizes ) )
    in case node.nodeType of
        Root def -> renderRoot def width height
        Rect def -> renderRect def width height
        Text def -> renderText def width height

renderRoot : RootDef -> Size -> Size -> Render
renderRoot def width height = 
    let rootRect =
            { background = black
            }
    in renderRect rootRect width height

renderRect : RectDef -> Size -> Size -> Render
renderRect def width height =
    ( rect width height |> filled def.background, ( width, height ) ) |> Right

renderText : TextDef -> Size -> Size -> Render
renderText def width height =
    --TODO if width or height is 0 make it Fit
    fromString def.text |> leftAligned |> Left


-- NODE PROPERTIES

type alias Size = Float
type alias Sizes = ( Float, Float )
type alias ISize = Int
type alias ISizes = ( ISize, ISize )
type alias Ratio = Float
type alias Extents = ( Extent, Extent )

type Extent =
    Fix Size
    | Fit
    | Fill Ratio

type Align = TopLeft | TopMiddle | TopRight
    | MiddleLeft | Middle | MiddleRight
    | BottomLeft | BottomMiddle | BottomRight

-- TODO collage and sizeOf use Int, but shapes use Float
toFloat2 : ( Int, Int ) -> ( Float, Float )
toFloat2 ( x, y ) = ( toFloat x, toFloat y )

toInt2 : ( Float, Float ) -> ( Int, Int )
toInt2 ( x, y ) = ( ceiling x, ceiling y )

