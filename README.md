# Partial Test Generator

## Usage

Include these steps on github actions
```yaml
- name: Get changed files
  id: changed-files
  uses: jitterbit/get-changed-files@v1
- name: Generate partial test
  if: ${{ vars.TEST_STRATEGY == 'PARTIAL' }}
  run: |
    mint run fernando-dialpad/PartialTestGenerator@main \
      project_path \
      root_package \
      test_plan \
      ${{ steps.changed-files.outputs.all }}
```
