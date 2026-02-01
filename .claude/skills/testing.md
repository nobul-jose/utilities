# Testing Skills

## Test-First Bug Fixing

When fixing bugs, follow this workflow:

1. **Reproduce the bug** - Write a test that fails due to the bug
2. **Verify the test** - Ensure the test actually captures the bug behavior
3. **Fix the code** - Make the minimal change to fix the issue
4. **Verify the fix** - Run the test to confirm it passes
5. **Check for regressions** - Run the full test suite

## Writing Good Tests

### Shell Script Testing

```bash
# Test function pattern
test_my_function() {
    local result
    result=$(my_function "input")

    if [[ "$result" != "expected" ]]; then
        echo "FAIL: my_function returned '$result', expected 'expected'"
        return 1
    fi
    echo "PASS: my_function"
}
```

### Python Testing

```python
import unittest

class TestMyFunction(unittest.TestCase):
    def test_basic_case(self):
        result = my_function("input")
        self.assertEqual(result, "expected")

    def test_edge_case(self):
        with self.assertRaises(ValueError):
            my_function(None)

if __name__ == "__main__":
    unittest.main()
```

## Integration Testing

For scripts that interact with external systems (StorNext, APIs):

1. Use mocks or test environments when possible
2. Document prerequisites clearly
3. Include dry-run modes for destructive operations
