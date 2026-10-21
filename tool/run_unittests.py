"""Run a required unittest suite; an empty discovery is an error on every Python."""
import argparse
import sys
import unittest

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--start', required=True)
    parser.add_argument('--pattern', required=True)
    args = parser.parse_args()
    suite = unittest.defaultTestLoader.discover(args.start, pattern=args.pattern)
    if suite.countTestCases() == 0:
        print(f'No tests discovered for required suite: {args.pattern}', file=sys.stderr)
        return 5
    return 0 if unittest.TextTestRunner(verbosity=2).run(suite).wasSuccessful() else 1

if __name__ == '__main__':
    raise SystemExit(main())
