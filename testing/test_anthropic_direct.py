#!/usr/bin/env python3
"""
Direct API key test - paste your key when prompted
"""
import sys
from anthropic import Anthropic
from anthropic import APIError

def test_key(api_key):
    """Test an API key directly."""
    if not api_key or not api_key.strip():
        print("❌ No API key provided")
        return False
    
    api_key = api_key.strip()
    
    # Remove quotes if present
    if api_key.startswith("'") and api_key.endswith("'"):
        api_key = api_key[1:-1]
    elif api_key.startswith('"') and api_key.endswith('"'):
        api_key = api_key[1:-1]
    
    print(f"Testing key (starts with: {api_key[:10]}...)")
    print(f"Key length: {len(api_key)} characters")
    
    if not api_key.startswith('sk-'):
        print("⚠️  Warning: Key doesn't start with 'sk-'")
    
    try:
        client = Anthropic(api_key=api_key)
        
        print("\nMaking test API call...")
        message = client.messages.create(
            model="claude-3-5-sonnet-20241022",
            max_tokens=20,
            messages=[
                {"role": "user", "content": "Say 'test successful'"}
            ]
        )
        
        response_text = message.content[0].text
        print(f"✅ SUCCESS! Response: {response_text}")
        print("\nYour API key is valid and working!")
        return True
        
    except APIError as e:
        status = getattr(e, 'status_code', None)
        msg = getattr(e, 'message', str(e))
        
        print(f"\n❌ API Error (Status: {status})")
        print(f"   {msg}")
        
        if status == 401:
            print("\n💡 Authentication failed - API key is invalid")
        elif status == 429:
            print("\n💡 Rate limit or quota exceeded")
            print("   - Check usage: https://console.anthropic.com/usage")
            print("   - Wait a few minutes and try again")
        elif status == 402:
            print("\n💡 Payment required - check your billing")
        else:
            print(f"\n💡 Error code {status} - see Anthropic docs")
        
        return False
    except Exception as e:
        print(f"\n❌ Error: {type(e).__name__}: {e}")
        return False

if __name__ == "__main__":
    if len(sys.argv) > 1:
        # Key provided as argument
        test_key(sys.argv[1])
    else:
        print("Anthropic API Key Tester")
        print("=" * 40)
        print("\nUsage:")
        print("  python3 test_anthropic_direct.py 'your-api-key-here'")
        print("\nOr paste your key (will be hidden):")
        import getpass
        key = getpass.getpass("API Key: ")
        test_key(key)
