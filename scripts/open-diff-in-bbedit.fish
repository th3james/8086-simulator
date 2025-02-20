#!/usr/bin/env fish

zig build; and begin
  set binary_file $argv[1]

  set emulation_output (string replace ".bin" ".txt" $binary_file)

  bbedit (diff (zig-out/bin/8086-simulator --execute $binary_file | psub) $emulation_output | psub)
end
