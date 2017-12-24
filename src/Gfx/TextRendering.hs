module Gfx.TextRendering
  ( createTextRenderer
  , renderText
  , renderTextbuffer
  , resizeTextRendererScreen
  , changeTextColour
  , textCoordMatrix
  , TextRenderer
  ) where

import           Control.Monad             (foldM_)
import           GHC.Int                   (Int32)

import           Foreign.Marshal.Array     (withArray)
import           Foreign.Marshal.Utils     (fromBool, with)
import           Foreign.Ptr               (castPtr, nullPtr)
import           Foreign.Storable          (peek, sizeOf)

import qualified Data.Map.Strict           as M

import           Gfx.FontHandling          (Character (..), Font (..),
                                            getCharacter, loadFont)
import           Gfx.GeometryBuffers       (bufferOffset, setAttribPointer)
import           Gfx.LoadShaders           (ShaderInfo (..), ShaderSource (..),
                                            loadShaders)
import qualified Graphics.GL               as GLRaw
import           Graphics.Rendering.OpenGL (ArrayIndex, AttribLocation (..),
                                            BlendEquation (FuncAdd),
                                            BlendingFactor (One, OneMinusSrcAlpha, SrcAlpha, Zero),
                                            BufferObject,
                                            BufferTarget (ArrayBuffer),
                                            BufferUsage (DynamicDraw),
                                            Capability (Enabled),
                                            ClearBuffer (ColorBuffer),
                                            Color4 (..), Color4,
                                            DataType (Float),
                                            FramebufferTarget (Framebuffer),
                                            GLfloat, IntegerHandling (ToFloat),
                                            NumArrayIndices,
                                            PrimitiveMode (Triangles), Program,
                                            ShaderType (FragmentShader, VertexShader),
                                            TextureTarget2D (Texture2D),
                                            TextureUnit (..),
                                            TransferDirection (WriteToBuffer),
                                            UniformLocation (..),
                                            VertexArrayDescriptor (..),
                                            VertexArrayObject, ($=))
import qualified Graphics.Rendering.OpenGL as GL

import           Gfx.PostProcessing        (Savebuffer (..), createSavebuffer,
                                            deleteSavebuffer, drawQuadVBO)

import           Data.Vec                  (Mat44, multmm)
import           Gfx.Matrices              (orthographicMat, translateMat)

import           ErrorHandling             (printErrors)

data CharQuad =
  CharQuad VertexArrayObject
           BufferObject
           ArrayIndex
           NumArrayIndices
  deriving (Show, Eq)

data TextRenderer = TextRenderer
  { textFont        :: Font
  , charSize        :: Int
  , pMatrix         :: Mat44 GLfloat
  , textprogram     :: Program
  , bgprogram       :: Program
  , characterQuad   :: CharQuad
  , characterBGQuad :: CharQuad
  , textColour      :: Color4 GLfloat
  , textBGColour    :: Color4 GLfloat
  , outbuffer       :: Savebuffer
  } deriving (Show)

textCoordMatrix :: Floating f => f -> f -> f -> f -> f -> f -> Mat44 f
textCoordMatrix left right top bottom near far =
  let o = orthographicMat left right top bottom near far
      t = translateMat (-1) 1 0
  in multmm t o

createCharacterQuad :: IO () -> IO CharQuad
createCharacterQuad quadConfig = do
  vao <- GL.genObjectName
  GL.bindVertexArrayObject $= Just vao
  arrayBuffer <- GL.genObjectName
  GL.bindBuffer ArrayBuffer $= Just arrayBuffer
  quadConfig
  GL.bindVertexArrayObject $= Nothing
  GL.bindBuffer ArrayBuffer $= Nothing
  return $ CharQuad vao arrayBuffer 0 6

createCharacterTextQuad :: IO CharQuad
createCharacterTextQuad =
  let vertexSize = fromIntegral $ sizeOf (0 :: GLfloat)
      firstPosIndex = 0
      firstTexIndex = 2 * vertexSize
      vPosition = AttribLocation 0
      vTexCoord = AttribLocation 1
      numVertices = 6 * 4
      size = fromIntegral (numVertices * vertexSize)
      stride = fromIntegral (4 * vertexSize)
      quadConfig = do
        GL.bufferData ArrayBuffer $= (size, nullPtr, DynamicDraw)
        setAttribPointer vPosition 2 stride firstPosIndex
        setAttribPointer vTexCoord 2 stride firstTexIndex
  in createCharacterQuad quadConfig

createCharacterBGQuad :: IO CharQuad
createCharacterBGQuad =
  let vertexSize = sizeOf (0 :: GLfloat)
      firstPosIndex = 0
      vPosition = AttribLocation 0
      numVertices = 6 * 2
      size = fromIntegral (numVertices * vertexSize)
      stride = 0
      quadConfig = do
        GL.bufferData ArrayBuffer $= (size, nullPtr, DynamicDraw)
        setAttribPointer vPosition 2 stride firstPosIndex
  in createCharacterQuad quadConfig

createTextRenderer ::
     Float
  -> Float
  -> Int
  -> Int
  -> Maybe FilePath
  -> Int
  -> Color4 GLfloat
  -> Color4 GLfloat
  -> IO TextRenderer
createTextRenderer front back width height fontPath charSize textColour bgColour = do
  cq <- createCharacterTextQuad
  cbq <- createCharacterBGQuad
  tprogram <-
    loadShaders
      [ ShaderInfo VertexShader (FileSource "shaders/textrenderer.vert")
      , ShaderInfo FragmentShader (FileSource "shaders/textrenderer.frag")
      ]
  bgshaderprogram <-
    loadShaders
      [ ShaderInfo VertexShader (FileSource "shaders/textrenderer-bg.vert")
      , ShaderInfo FragmentShader (FileSource "shaders/textrenderer-bg.frag")
      ]
  font <- loadFont fontPath charSize
  let projectionMatrix =
        textCoordMatrix
          0
          (fromIntegral width)
          0
          (fromIntegral height)
          front
          back
  buffer <- createSavebuffer (fromIntegral width) (fromIntegral height)
  return $
    TextRenderer
      font
      charSize
      projectionMatrix
      tprogram
      bgshaderprogram
      cq
      cbq
      textColour
      bgColour
      buffer

resizeTextRendererScreen ::
     Float -> Float -> Int -> Int -> TextRenderer -> IO TextRenderer
resizeTextRendererScreen front back width height trender =
  let projectionMatrix =
        textCoordMatrix
          0
          (fromIntegral width)
          0
          (fromIntegral height)
          front
          back
  in do deleteSavebuffer $ outbuffer trender
        nbuffer <- createSavebuffer (fromIntegral width) (fromIntegral height)
        return trender {pMatrix = projectionMatrix, outbuffer = nbuffer}

changeTextColour :: Color4 GLfloat -> TextRenderer -> TextRenderer
changeTextColour newColour trender = trender {textColour = newColour}

renderText :: Int -> Int -> TextRenderer -> String -> IO ()
renderText xpos ypos renderer strings = do
  let (Savebuffer fbo _ _ _ _) = outbuffer renderer
  GL.bindFramebuffer Framebuffer $= fbo
  renderCharacters xpos ypos renderer strings
  printErrors

renderTextbuffer :: TextRenderer -> IO ()
renderTextbuffer renderer = do
  GL.bindFramebuffer Framebuffer $= GL.defaultFramebufferObject
  let (Savebuffer _ text _ program quadVBO) = outbuffer renderer
  GL.currentProgram $= Just program
  GL.activeTexture $= TextureUnit 0
  GL.textureBinding Texture2D $= Just text
  drawQuadVBO quadVBO

renderCharacters :: Int -> Int -> TextRenderer -> String -> IO ()
renderCharacters xpos ypos renderer strings = do
  GL.blend $= Enabled
  GL.blendEquationSeparate $= (FuncAdd, FuncAdd)
  GL.blendFuncSeparate $= ((SrcAlpha, OneMinusSrcAlpha), (One, Zero))
  GL.depthFunc $= Nothing
  GL.clearColor $= Color4 0.0 0.0 0.0 0.0
  GL.clear [ColorBuffer]
  let font = textFont renderer
  foldM_
    (\(xp, yp) c ->
       case c of
         '\n' -> return (xpos, yp + fontHeight font)
         _ ->
           maybe
             (return (xp, yp + fontAdvance font))
             (\c -> renderChar c xp yp font)
             (getCharacter font c))
    (xpos, ypos)
    strings
  where
    renderChar char xp yp f = do
      renderCharacterBGQuad renderer char xp yp f
      renderCharacterTextQuad renderer char xp yp f

sendProjectionMatrix :: Program -> Mat44 GLfloat -> IO ()
sendProjectionMatrix program mat = do
  (UniformLocation projU) <- GL.get $ GL.uniformLocation program "projection"
  with mat $ GLRaw.glUniformMatrix4fv projU 1 (fromBool True) . castPtr

sendVertices :: [GLfloat] -> IO ()
sendVertices verts =
  let vertSize = sizeOf (head verts)
      numVerts = length verts
      size = fromIntegral (numVerts * vertSize)
  in withArray verts $ \ptr ->
       GL.bufferSubData ArrayBuffer WriteToBuffer 0 size ptr

renderCharacterQuad ::
     Program -> Mat44 GLfloat -> CharQuad -> IO () -> [GLfloat] -> IO ()
renderCharacterQuad program pMatrix character charDrawFunc charVerts =
  let (CharQuad arrayObject arrayBuffer firstIndex numTriangles) = character
  in do GL.currentProgram $= Just program
        GL.bindVertexArrayObject $= Just arrayObject
        GL.bindBuffer ArrayBuffer $= Just arrayBuffer
        charDrawFunc
        sendProjectionMatrix program pMatrix
        sendVertices charVerts
        GL.drawArrays Triangles firstIndex numTriangles
        printErrors

renderCharacterTextQuad ::
     TextRenderer -> Character -> Int -> Int -> Font -> IO (Int, Int)
renderCharacterTextQuad renderer (Character c width height adv xBearing yBearing text) x y font =
  let baseline = fromIntegral (y + fontAscender font)
      gX1 = fromIntegral (x + xBearing)
      gX2 = gX1 + fromIntegral width
      gY1 = baseline - fromIntegral yBearing
      gY2 = gY1 + fromIntegral height
      charVerts =
        [ gX1
        , gY1
        , 0.0
        , 0.0 -- coord 1
        , gX1
        , gY2
        , 0.0
        , 1.0 -- coord 2
        , gX2
        , gY1
        , 1.0
        , 0.0 -- coord 3
        , gX1
        , gY2
        , 0.0
        , 1.0 -- coord 4
        , gX2
        , gY2
        , 1.0
        , 1.0 -- coord 5
        , gX2
        , gY1
        , 1.0
        , 0.0 -- coord 6
        ] :: [GLfloat]
      charDrawFunc = do
        GL.activeTexture $= TextureUnit 0
        GL.textureBinding Texture2D $= Just text
        textColourU <-
          GL.get $ GL.uniformLocation (textprogram renderer) "textColor"
        GL.uniform textColourU $= textColour renderer
        textBGColourU <-
          GL.get $ GL.uniformLocation (textprogram renderer) "textBGColor"
        GL.uniform textBGColourU $= textBGColour renderer
  in do renderCharacterQuad
          (textprogram renderer)
          (pMatrix renderer)
          (characterQuad renderer)
          charDrawFunc
          charVerts
        return (x + adv, y)

renderCharacterBGQuad ::
     TextRenderer -> Character -> Int -> Int -> Font -> IO ()
renderCharacterBGQuad renderer (Character _ _ _ adv _ _ _) x y font =
  let x1 = fromIntegral x
      x2 = fromIntegral $ x + adv
      y1 = fromIntegral y
      y2 = fromIntegral $ y + fontHeight font
      charVerts = [x1, y1, x1, y2, x2, y1, x1, y2, x2, y2, x2, y1] :: [GLfloat]
      charDrawFunc = do
        textBGColourU <-
          GL.get $ GL.uniformLocation (bgprogram renderer) "textBGColor"
        GL.uniform textBGColourU $= textBGColour renderer
  in renderCharacterQuad
       (bgprogram renderer)
       (pMatrix renderer)
       (characterBGQuad renderer)
       charDrawFunc
       charVerts
