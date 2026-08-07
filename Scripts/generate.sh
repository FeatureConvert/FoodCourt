#!/bin/bash
# Regenerates Fable.xcodeproj from project.yml.
#
# Two things xcodegen 2.46 cannot express are patched in afterwards:
#   1. It writes the StoreKit configuration path one directory level too shallow
#      ("../../..." is relative to the scheme file, so it needs three levels to reach
#      the repo root, not two).
#   2. It only emits the reference on the Run action, never the Test action.
set -euo pipefail
cd "$(dirname "$0")/.."

xcodegen generate

python3 - "Fable.xcodeproj/xcshareddata/xcschemes/Fable.xcscheme" <<'PY'
import sys
path = sys.argv[1]
scheme = open(path).read()
reference = '''      <StoreKitConfigurationFileReference
         identifier = "../../../Sources/Store/Products.storekit">
      </StoreKitConfigurationFileReference>
'''
scheme = scheme.replace('identifier = "../../Sources/Store/Products.storekit"',
                        'identifier = "../../../Sources/Store/Products.storekit"')
if 'StoreKitConfigurationFileReference' not in scheme.split('</TestAction>')[0]:
    scheme = scheme.replace('   </TestAction>', reference + '   </TestAction>', 1)
open(path, 'w').write(scheme)
PY

echo "Generated Fable.xcodeproj (StoreKit configuration wired into Run and Test)."
