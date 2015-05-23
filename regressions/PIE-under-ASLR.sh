cc -fPIE -pie -Wl,-Ttext-segment=0x6ABC55000000 -xc - <<'EOL'
/** https://bugzilla.kernel.org/show_bug.cgi?id=66721 */

#include <stdio.h>

char foo[132121799];

int
main ()
{
  foo[sizeof (foo) - 2] = -34;
  printf ("%p, %d\n", &main, foo[sizeof (foo) - 2]);
  return 0;
}
EOL

for i in {0..2}; do
    echo 0 >| /proc/sys/kernel/randomize_va_space
    current="$(./a.out)"

    if [ -n "$prev" ] && [ ! "$current" = "$prev" ]; then
        echo "Failed for $i ('$prev' VS '$current')" >&2
        exit 1
    fi

    prev="$current"
done
