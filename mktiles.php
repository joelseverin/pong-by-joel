#!/usr/bin/php
<?php
/*
  ; Pong by Joel - a pong game for SNES.
  ; Copyright (C) 2013 Joel Severin
  ; 
  ; This program is free software: you can redistribute it and/or modify
  ; it under the terms of the GNU General Public License as published by
  ; the Free Software Foundation, either version 3 of the License, or
  ; (at your option) any later version.
  ; 
  ; This program is distributed in the hope that it will be useful,
  ; but WITHOUT ANY WARRANTY; without even the implied warranty of
  ; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
  ; GNU General Public License for more details.
  ; 
  ; You should have received a copy of the GNU General Public License
  ; along with this program. If not, see <http://www.gnu.org/licenses/>.
*/

/*
 * This file is a quick hack to get a tile map binary. SNES uses bitplanes in an interleaved format:
 * 
 * Everything is stored in 8x8 tiles with the following format:
 * for 1 to 8: bitplane0
 *             bitplane1
 * endfor
 * for 1 to 8: bitplane2
 *             bitplane3
 * endfor
 * 
 * bitplane 0 is the LSB, which is the only one we currently use (0 = color 0, 1 = color 1).
 * The others are 0. To our help, we can use str_repeat. Pay special attention to the "\x" syntax,
 * which doesn't work for every character. One example: "\0" == chr(0) but "\165" != chr(165).
 * Use chr instead for anything except \0!
 */

// Generate this:
// 0 0000 0000 0000 0000
// 1 b000 0000 0000 0000 (b = This is the ball, 8x8)
// 2 Xooo 0000 Chr0 Chr1 (X = This is the paddle, (4*8)x(4*8) = 32x32)
// 3 Xooo 0000 Chr0 Chr1 (o = 0, just written as o to denote which 8x8 tiles is part of the paddle)
// 4 Xooo 0000 Chr0 Chr1
// 5 Xooo 0000 Chr0 Chr1
// 6 Chr2 Chr3 Chr4 Chr5
// 7 Chr2 Chr3 Chr4 Chr5
// 8 Chr2 Chr3 Chr4 Chr5
// 9 Chr2 Chr3 Chr4 Chr5
// A Chr6 Chr7 Chr8 Chr9
// B Chr6 Chr7 Chr8 Chr9
// C Chr6 Chr7 Chr8 Chr9
// D Chr6 Chr7 Chr8 Chr9
// E 0000 0000 0000 0000
// F 0000 0000 0000 0000

function makeBall8x8() {
  $ball = array(
    0b00011000,
    0b00111100,
    0b01111110,
    0b11111111,
    0b11111111,
    0b01111110,
    0b00111100,
    0b00011000
  );

  return makeFromBitmaskPattern8x8($ball);
}

function makeFromBitmaskPattern8x8($pattern) {
  $out = "";
  foreach($pattern as $bits) {
    $out .= chr($bits) . "\0";
  }
  $out .= str_repeat("\0", 16);
  return $out;
}

function makeSolid8x8() {
  return str_repeat("\1\0", 8) . str_repeat("\0", 16);
}

function makeEmpty8x8() {
  return str_repeat("\0", 32);
}

function makeChar4x4x8x8($index) {
  // Like in a 7-segment display (but different order than the strange standard...).
  // 111
  // 2 3
  // 444
  // 5 6
  // 777
  $numbers = array(
    //76543210 - which "areas" to activate (make color 1)
    0b11101110,//0
    0b01001000,//1
    0b10111010,//2
    0b11011010,//3
    0b01011100,//4
    0b11010110,//5
    0b11110110,//6
    0b01001010,//7
    0b11111110,//8
    0b01011110,//9
  );
  
  // A segment bitmap. Open 7seg.bmp with a TEXT EDITOR to get this (it's a color code <=> ASCII haxx).
  $segments = array(
    array(0, 0, 0, 1 ,1 ,1 ,1 ,1 ,1 ,1 ,1 ,1 ,1 ,0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0),
    array(0, 0, 1 ,1 ,1 ,1 ,1 ,1 ,1 ,1 ,1 ,1 ,1 ,1 ,0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0),
    array(0, 0, 0, 1 ,1 ,1 ,1 ,1 ,1 ,1 ,1 ,1 ,1 ,0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0),
    array(0, 2 ,0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3 ,0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0),
    array(2, 2, 2 ,0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3, 3, 3 ,0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0),
    array(2, 2, 2 ,0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3, 3, 3 ,0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0),
    array(2, 2, 2 ,0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3, 3, 3 ,0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0),
    array(2, 2, 2 ,0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3, 3, 3 ,0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0),
    array(2, 2, 2 ,0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3, 3, 3 ,0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0),
    array(2, 2, 2 ,0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3, 3, 3 ,0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0),
    array(2, 2, 2 ,0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3, 3, 3 ,0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0),
    array(2, 2, 2 ,0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3, 3, 3 ,0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0),
    array(2, 2, 2 ,0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3, 3, 3 ,0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0),
    array(0, 2 ,0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3 ,0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0),
    array(0, 0, 0, 4 ,4 ,4 ,4 ,4 ,4 ,4 ,4 ,4 ,4 ,0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0),
    array(0, 0, 4 ,4 ,4 ,4 ,4 ,4 ,4 ,4 ,4 ,4 ,4 ,4 ,0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0),
    array(0, 0, 0, 4 ,4 ,4 ,4 ,4 ,4 ,4 ,4 ,4 ,4 ,0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0),
    array(0, 5 ,0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 6 ,0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0),
    array(5, 5, 5 ,0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 6, 6, 6 ,0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0),
    array(5, 5, 5 ,0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 6, 6, 6 ,0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0),
    array(5, 5, 5 ,0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 6, 6, 6 ,0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0),
    array(5, 5, 5 ,0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 6, 6, 6 ,0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0),
    array(5, 5, 5 ,0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 6, 6, 6 ,0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0),
    array(5, 5, 5 ,0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 6, 6, 6 ,0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0),
    array(5, 5, 5 ,0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 6, 6, 6 ,0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0),
    array(5, 5, 5 ,0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 6, 6, 6 ,0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0),
    array(5, 5, 5 ,0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 6, 6, 6 ,0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0),
    array(5, 5, 5 ,0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 6, 6, 6 ,0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0),
    array(0, 5 ,0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 6 ,0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0),
    array(0, 0, 0, 7 ,7 ,7 ,7 ,7 ,7 ,7 ,7 ,7 ,7 ,0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0),
    array(0, 0, 7 ,7 ,7 ,7 ,7 ,7 ,7 ,7 ,7 ,7 ,7 ,7 ,0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0),
    array(0, 0, 0, 7 ,7 ,7 ,7 ,7 ,7 ,7 ,7 ,7 ,7 ,0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0),
  );

  $numberMask = $numbers[$index];
  
  $result = array();
  for($row = 0; $row < 4; $row++) {
    $rowResult = array();
    for($column = 0; $column < 4; $column++) {
      // Let's create an individual tile here
      $tile = "";
      
      for($tileRow = 0; $tileRow < 8; $tileRow++) {
        $bitPlane0 = 0;
        for($bit = 7; $bit >= 0; $bit--) {
          $bitPlane0 <<= 1;
          $bitType = $segments[$row*8 + $tileRow][$column*8 + (7 - $bit)]; // E.g. 0, 1, 2, ..., 7.
          $bitPlane0 |= (($numberMask >> $bitType) & 1 != 0) ? 1 : 0;
        }
        $tile .= chr($bitPlane0) . "\0"; // bitPlane1 = 0
      }
      
      // bitPlane2 and bitPlane3 is all 0
      $tile .= str_repeat("\0\0", 8);
      
      $rowResult[] = $tile;
    }
    $result[] = $rowResult;
  }
    
  return $result;
}

function makePaddle4x4x8x8() {
  return array(
    array(makeSolid8x8(), makeEmpty8x8(), makeEmpty8x8(), makeEmpty8x8()),
    array(makeSolid8x8(), makeEmpty8x8(), makeEmpty8x8(), makeEmpty8x8()),
    array(makeSolid8x8(), makeEmpty8x8(), makeEmpty8x8(), makeEmpty8x8()),
    array(makeSolid8x8(), makeEmpty8x8(), makeEmpty8x8(), makeEmpty8x8())
  );
}

function makeEmpty4x4x8x8() {
  return array(
    array(makeEmpty8x8(), makeEmpty8x8(), makeEmpty8x8(), makeEmpty8x8()),
    array(makeEmpty8x8(), makeEmpty8x8(), makeEmpty8x8(), makeEmpty8x8()),
    array(makeEmpty8x8(), makeEmpty8x8(), makeEmpty8x8(), makeEmpty8x8()),
    array(makeEmpty8x8(), makeEmpty8x8(), makeEmpty8x8(), makeEmpty8x8())
  );
}

///////////////////////////////////////////////////////////////////////////////

$fp = fopen("tiles.bin", "w");// w = truncate to 0-length, open in write mode...

// Fill 1:st row with 0s
for($i = 0; $i < 16; $i++) {
  fwrite($fp, makeEmpty8x8());
}

// Fill 2:nd row with ball + 0:s
fwrite($fp, makeBall8x8());
for($i = 0; $i < 15; $i++) {
  fwrite($fp, makeEmpty8x8());
}

// Create a 3x4 matrix with this:
// The cells should consist of a 4x4 matrix with indexing matrix[row][column], where each of its
// cells should consist of a 8x8 tile (a byte-array as a PHP string, in native tile format).
$matrix = array(
  array(makePaddle4x4x8x8(), makeEmpty4x4x8x8(), makeChar4x4x8x8(0), makeChar4x4x8x8(1)),
  array(makeChar4x4x8x8(2), makeChar4x4x8x8(3), makeChar4x4x8x8(4), makeChar4x4x8x8(5)),
  array(makeChar4x4x8x8(6), makeChar4x4x8x8(7), makeChar4x4x8x8(8), makeChar4x4x8x8(9))
);
foreach($matrix as $matrixRow) {
  for($rowIndex = 0; $rowIndex < 4; $rowIndex++) {
    foreach($matrixRow as $matrixCell) {
      foreach($matrixCell[$rowIndex] as $cell) {
        fwrite($fp, $cell);
      }
    }
  }
}

// Fill the 2 bottom lines with 0:s
for($j = 0; $j < 2; $j++) {
  for($i = 0; $i < 16; $i++) {
    fwrite($fp, makeEmpty8x8());
  }
}

fclose($fp);

echo "Tiles generated.\n";