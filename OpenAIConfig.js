/**
 * OpenAIConfig.js
 * JavaScript implementation of OpenAI configuration
 * 
 * Created by CAIT on 3/29/25.
 */

class OpenAIConfig {
    // Replace with your actual OpenAI API key
    static get apiKey() {
        return "sk-proj--.....";
    }
    
    static get baseURL() {
        return "https://api.openai.com/v1";
    }
}

// Alternative implementation using a plain object
const OpenAIConfigObject = {
    // Replace with your actual OpenAI API key
    apiKey: "sk-proj--.....",
    baseURL: "https://api.openai.com/v1"
};

// Export for use in modules
export { OpenAIConfig, OpenAIConfigObject };

// For CommonJS environments
if (typeof module !== 'undefined' && module.exports) {
    module.exports = { OpenAIConfig, OpenAIConfigObject };
} 