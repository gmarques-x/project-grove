load helpers
setup() { gt_test_setup; }

HELPER() { /usr/bin/python3 -I "$GT_ROOT/lib/wallpaper_store.py" "$@"; }

@test "wallpaper_store rewrites every Desktop entry and prints the count" {
  gt_make_store "$BATS_TEST_TMPDIR/Index.plist"
  run HELPER "$BATS_TEST_TMPDIR/Index.plist" "/tmp/my dir/w p.png"
  [ "$status" -eq 0 ]
  [ "$output" = 7 ]
  [ "$(gt_store_urls "$BATS_TEST_TMPDIR/Index.plist" | sort -u)" = "file:///tmp/my%20dir/w%20p.png" ]
  [ "$(gt_store_urls "$BATS_TEST_TMPDIR/Index.plist" | wc -l | tr -d ' ')" = 7 ]
  [ "$(gt_store_idle "$BATS_TEST_TMPDIR/Index.plist" | wc -l | tr -d ' ')" = 7 ]
  [ "$(gt_store_idle "$BATS_TEST_TMPDIR/Index.plist" | sort -u)" = "com.apple.wallpaper.choice.aerials:idle" ]
  [ ! -e "$BATS_TEST_TMPDIR/Index.plist.tmp" ]
}

@test "wallpaper_store fails with a message when the store is missing or unreadable" {
  run HELPER "$BATS_TEST_TMPDIR/none.plist" /tmp/x.png
  [ "$status" -eq 1 ]
  [ -n "$output" ]
  echo "not a plist" > "$BATS_TEST_TMPDIR/bad.plist"
  run HELPER "$BATS_TEST_TMPDIR/bad.plist" /tmp/x.png
  [ "$status" -eq 1 ]
  [ -n "$output" ]
  [ "$(cat "$BATS_TEST_TMPDIR/bad.plist")" = "not a plist" ]
}
