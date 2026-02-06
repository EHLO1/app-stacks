# n8n Python Code Node - Test Script
# Paste this into a Python Code node to verify packages are working

# Test imports
import requests
import pandas as pd
import numpy as np

results = {
    "packages": {},
    "tests": {}
}

# Package versions
results["packages"] = {
    "requests": requests.__version__,
    "pandas": pd.__version__,
    "numpy": np.__version__,
}

# Test 1: NumPy array operations
arr = np.array([1, 2, 3, 4, 5])
results["tests"]["numpy_sum"] = int(np.sum(arr))
results["tests"]["numpy_mean"] = float(np.mean(arr))

# Test 2: Pandas DataFrame
df = pd.DataFrame({
    "name": ["Alice", "Bob", "Charlie"],
    "score": [85, 92, 78]
})
results["tests"]["pandas_rows"] = len(df)
results["tests"]["pandas_mean_score"] = float(df["score"].mean())

# Test 3: Requests (httpbin echo)
try:
    resp = requests.get("https://httpbin.org/get", timeout=5)
    results["tests"]["requests_status"] = resp.status_code
    results["tests"]["requests_ok"] = resp.ok
except Exception as e:
    results["tests"]["requests_error"] = str(e)

return results