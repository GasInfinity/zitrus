# Mango Samples

Sample programs for using the mango graphics API.

## Overview

If you are familiarized with modern graphics apis, you'll feel at home with mango as it maintains a lot of the core values
found in them, naming some:
  
- **Explicit memory management**: You MUST manage GPU memory if you want to achieve greatest performance.
- **Explicit GPU<->CPU synchronization**: You MUST synchronize with the GPU as it runs in parallel, it's an independent device!
- **Stateless**: Command buffers are independent! You MUST know the full pipeline state upfront (good for the driver as it could optimize things!), that doesn't mean you can't use dynamic state (which you should if you need to)!
