#!/usr/bin/env python3
"""
Diagnostic script to test Anthropic API key and identify issues.
"""
import os
import sys
from anthropic import Anthropic
from anthropic import APIError

def test_api_key():
    """Test if Anthropic API key is configured and working."""
    
    # Check for API key in environment variable
    api_key = os.environ.get('ANTHROPIC_API_KEY')
    
    if not api_key:
        print("❌ ANTHROPIC_API_KEY environment variable not set")
        print("\nNote: Cursor stores the API key in its own settings, not as an env var.")
        print("\nTo test your API key manually:")
        print("1. Get your API key from: https://console.anthropic.com/settings/keys")
        print("2. Set it temporarily: export ANTHROPIC_API_KEY='your-key-here'")
        print("3. Run this script again")
        return False
    
    # Validate key format
    if not api_key.startswith('sk-'):
        print(f"⚠️  Warning: API key doesn't start with 'sk-' (found: {api_key[:5]}...)")
        print("   Anthropic API keys typically start with 'sk-'")
    
    print(f"✓ Found API key (starts with: {api_key[:10]}...)")
    print(f"✓ Key length: {len(api_key)} characters")
    
    try:
        client = Anthropic(api_key=api_key)
        
        # Make a simple test request
        print("\nTesting API connection...")
        message = client.messages.create(
            model="claude-3-5-sonnet-20241022",
            max_tokens=10,
            messages=[
                {"role": "user", "content": "Say 'API test successful' if you can read this."}
            ]
        )
        
        response_text = message.content[0].text
        print(f"✓ API Response: {response_text}")
        print("\n✅ Anthropic API key is working correctly!")
        return True
        
    except APIError as e:
        error_type = type(e).__name__
        status_code = getattr(e, 'status_code', None)
        
        print(f"\n❌ API Error: {error_type}")
        print(f"   Status Code: {status_code}")
        print(f"   Message: {e.message if hasattr(e, 'message') else str(e)}")
        
        if status_code == 401:
            print("\n💡 This indicates an authentication error:")
            print("   - API key is invalid or incorrect")
            print("   - API key may have been revoked")
            print("   - Check your key at: https://console.anthropic.com/settings/keys")
        elif status_code == 429:
            print("\n💡 This indicates rate limiting or quota exceeded:")
            print("   - You've hit rate limits (too many requests)")
            print("   - Your API quota may be exhausted")
            print("   - Check usage at: https://console.anthropic.com/usage")
            print("   - Wait a few minutes and try again")
        elif status_code == 500 or status_code >= 500:
            print("\n💡 This indicates a server error:")
            print("   - Anthropic's API may be experiencing issues")
            print("   - Try again in a few minutes")
        else:
            print(f"\n💡 Status code {status_code} - check Anthropic API documentation")
        
        return False
        
    except Exception as e:
        error_type = type(e).__name__
        print(f"\n❌ Unexpected error: {error_type}")
        print(f"   Message: {str(e)}")
        return False

if __name__ == "__main__":
    print("Anthropic API Key Diagnostic Tool")
    print("=" * 50)
    success = test_api_key()
    sys.exit(0 if success else 1)
