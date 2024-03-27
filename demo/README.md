# Demo with terminalizer

## Recording

Provided you have [terminalizer] installed, run the following from the top
directory of this repository.

```bash
terminalizer record demo/demo.yml --config demo/config.yml
```

## Verifying

Once done, use the [`play`][play] sub-command to verify your recording. You
might want to remove output lines from the YAML, alternatively change the pace.

## Render

Finally, run the following command to generate the animated GIF

```bash
terminalizer render demo/demo.yml --output demo/demo.gif
```

  [terminalizer]: https://github.com/faressoft/terminalizer
  [play]: https://github.com/faressoft/terminalizer?tab=readme-ov-file#play

## Optimise

Once generated, you can optimise the size of the target GIF using online
converters, e.x. [xconvert]. At [xconvert], use the following options:

+ Keep original quality
+ Keep original size
+ Reduce the colour palette and keep 128 colours
+ Drop every second frame.

  [xconvert]: https://www.xconvert.com/compress-gif
