# E2E Testing Issue: Material3 SearchBar Text Input

## Status: RESOLVED

The issue was resolved by replacing Material3's `SearchBar` component with a standard `OutlinedTextField`, which works correctly with Compose testing's `performTextInput()`.

## Original Problem

The E2E UI tests could not successfully input text into the Material3 `SearchBar` component using Compose testing's `performTextInput()`. Tests that verify search screen initialization pass, but any test requiring text input times out waiting for search results.

## What We Tried

### 1. Test tag on InputField modifier
```kotlin
SearchBarDefaults.InputField(
    // ...
    modifier = Modifier.testTag(TestTags.SEARCH_INPUT)
)
```
**Result:** Tag not found or input not working

### 2. Finding by placeholder text
```kotlin
composeTestRule
    .onNodeWithText("Search words...")
    .performClick()
    .performTextInput("hello")
```
**Result:** Click works, but text input doesn't trigger ViewModel's `onQueryChange`

### 3. Different test rule configurations
- `createComposeRule()` - No Activity context for AndroidViewModel
- `createAndroidComposeRule<MainActivity>()` - Activity launches before test DB setup
- `createEmptyComposeRule()` + `ActivityScenario.launch()` - Best approach, but still input issues

## Root Cause Analysis

Material3's `SearchBar` component has complex semantics:
1. It uses `SearchBarDefaults.InputField` which wraps a `TextField`
2. The expanded/collapsed state affects input handling
3. The `onQueryChange` callback may not fire from test input the same way as real input

The issue is likely that:
- Compose UI testing's `performTextInput()` bypasses the normal IME flow
- SearchBar's internal state management doesn't react to programmatic text changes
- The debounced search in ViewModel (300ms) may not trigger in test timing

## Potential Solutions

### Option A: Use Semantics Actions
```kotlin
composeTestRule
    .onNodeWithTag(TestTags.SEARCH_INPUT)
    .performSemanticsAction(SemanticsActions.SetText) {
        it("hello")
    }
```

### Option B: Use TextField directly in tests
Replace `SearchBar` with a simpler `TextField` when running in test mode, or create a testable wrapper.

### Option C: Use UiAutomator for text input
```kotlin
val device = UiDevice.getInstance(InstrumentationRegistry.getInstrumentation())
val searchField = device.findObject(UiSelector().text("Search words..."))
searchField.setText("hello")
```

### Option D: Inject test query via ViewModel
```kotlin
// In test setup, directly call ViewModel
viewModel.onQueryChange("hello")
```
This tests less of the UI but verifies the flow works.

### Option E: Wait for Material3 fix
Track: https://issuetracker.google.com/issues?q=SearchBar%20compose%20test

## Current Status

- **5 E2E tests pass** (all tests enabled and working)
- 22 integration tests pass (JNI boundary coverage)
- Tests use standard `performTextInput()` which works with `OutlinedTextField`

## Applied Solution

Replaced `SearchBar` with `OutlinedTextField` in `SearchScreen.kt`:

```kotlin
// Before: Material3 SearchBar (testing issues)
SearchBar(
    inputField = {
        SearchBarDefaults.InputField(
            query = query,
            onQueryChange = viewModel::onQueryChange,
            // ...
        )
    },
    // ...
)

// After: OutlinedTextField (works with Compose testing)
OutlinedTextField(
    value = query,
    onValueChange = viewModel::onQueryChange,
    placeholder = { Text("Search words...") },
    leadingIcon = { Icon(Icons.Default.Search, contentDescription = "Search") },
    trailingIcon = {
        if (query.isNotEmpty()) {
            IconButton(onClick = { viewModel.onQueryChange("") }) {
                Icon(Icons.Default.Clear, contentDescription = "Clear")
            }
        }
    },
    singleLine = true,
    modifier = Modifier
        .fillMaxWidth()
        .padding(horizontal = 16.dp, vertical = 8.dp)
        .testTag(TestTags.SEARCH_INPUT)
)
```

Tests now use straightforward text input:
```kotlin
private fun typeInSearchField(text: String) {
    composeTestRule
        .onNodeWithTag(TestTags.SEARCH_INPUT)
        .performTextInput(text)
    Thread.sleep(500)  // Wait for debounce
    composeTestRule.waitForIdle()
}
```

### Trade-offs
- Lost SearchBar's pill-shaped styling (minor visual change)
- Gained proper test compatibility with standard Compose testing APIs
- No workarounds needed - tests directly interact with UI as users would

## Files Involved

- `DictAppE2ETest.kt` - E2E test class with @Ignore annotations
- `SearchScreen.kt` - Contains the SearchBar component
- `TestTags.kt` - Test tag constants

## References

- [Compose Testing Cheatsheet](https://developer.android.com/jetpack/compose/testing-cheatsheet)
- [Material3 SearchBar API](https://developer.android.com/reference/kotlin/androidx/compose/material3/package-summary#SearchBar)
- [Known SearchBar testing issues](https://issuetracker.google.com/issues?q=SearchBar%20compose%20test)
