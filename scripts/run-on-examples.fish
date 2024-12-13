#!/usr/bin/env fish

zig build; and begin
  for binary_file in test-data/*.bin
    set source_file (string replace ".bin" ".asm" $binary_file)
    set emulation_output (string replace ".bin" ".txt" $binary_file)

    echo "diffing output for" $source_file
    diff (
      ./zig-out/bin/8086-simulator $binary_file | grep -vE '^\s*;|^\s*$' | psub
    ) (
      cat $source_file | grep -vE '^\s*;|^\s*$' | psub
    )

    if test -f $emulation_output
      echo "comparing emulation output for" $emulation_output
      diff (
        ./zig-out/bin/8086-simulator --execute $binary_file | grep -vE '^\s*$' | psub
      ) (
        cat $emulation_output | grep -vE '^\s*;|^\s*$' | psub
      )
    end
  end
end
