#!/usr/bin/env fish

zig build; and begin
  set binary_file $argv[1]
  set source_file_name (basename $binary_file)

  set source_file (string replace ".bin" ".asm" $binary_file)
  set emulation_output (string replace ".bin" ".txt" $binary_file)

  bbedit (
    diff (
      ./zig-out/bin/8086-simulator $binary_file | grep -vE '^\s*;|^\s*$' | psub
    ) (
      cat $source_file | grep -vE '^\s*;|^\s*$' | psub
    ) | psub -s $source_file_name.asm
  )

  bbedit (
    diff (
      ./zig-out/bin/8086-simulator --execute $binary_file | psub
    ) (
      cat $emulation_output | psub
    ) | psub -s $source_file_name.txt
  )
end
