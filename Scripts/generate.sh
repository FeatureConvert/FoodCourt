#!/bin/bash
# Regenerates Fable.xcodeproj from project.yml.
#
# One thing xcodegen 2.46 cannot express is patched in afterwards: it only emits the
# StoreKit configuration reference on the Run action, never the Test action. xcodegen's
# own path for the Run action ("../../Sources/Store/Products.storekit") is correct as-is
# and must not be touched — an earlier version of this script "corrected" it to three
# levels, which actually broke it. Confirmed via Xcode's own issue navigator: three levels
# resolves one directory too high, dropping the repo root ("Fable") from the path entirely.
set -euo pipefail
cd "$(dirname "$0")/.."

xcodegen generate

python3 - "Fable.xcodeproj/xcshareddata/xcschemes/Fable.xcscheme" <<'PY'
import sys
path = sys.argv[1]
scheme = open(path).read()
reference = '''      <StoreKitConfigurationFileReference
         identifier = "../../Sources/Store/Products.storekit">
      </StoreKitConfigurationFileReference>
'''
if 'StoreKitConfigurationFileReference' not in scheme.split('</TestAction>')[0]:
    scheme = scheme.replace('   </TestAction>', reference + '   </TestAction>', 1)
open(path, 'w').write(scheme)
PY

echo "Generated Fable.xcodeproj (StoreKit configuration wired into Run and Test)."
