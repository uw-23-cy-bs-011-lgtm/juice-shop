import { Component, ChangeDetectorRef, inject, OnInit } from '@angular/core'
import { KeysService } from '../Services/keys.service'
import { SnackBarHelperService } from '../Services/snack-bar-helper.service'
import { ethers } from 'ethers'
import {
  createClient,
  connect,
  disconnect,
  getAccount,
  InjectedConnector
} from '@wagmi/core'
import { solidityCompiler } from 'solidity-browser-compiler'
import { MatInputModule } from '@angular/material/input'
import { MatFormFieldModule, MatLabel } from '@angular/material/form-field'
import { TranslateModule } from '@ngx-translate/core'
import { MatButtonModule } from '@angular/material/button'
import { FormsModule } from '@angular/forms'
import { CodemirrorModule } from '@ctrl/ngx-codemirror'
import { MatIconModule } from '@angular/material/icon'

/**
 * Narrowly typed window.ethereum reference
 */
declare global {
  interface Window {
    ethereum?: {
      on: (event: string, handler: (...args: any[]) => void) => void;
      request: (args: { method: string; params?: any[] }) => Promise<any>;
      removeListener?: (event: string, handler: (...args: any[]) => void) => void;
    }
  }
}

/**
 * Use explicit provider only when needed; avoid autoConnect to reduce surprise connections.
 */
const client = createClient({
  autoConnect: false
})

/**
 * Whitelist compiler releases to avoid arbitrary remote code loads.
 * Keep versions small and reviewed.
 */
const compilerReleases: Record<string, string> = {
  '0.8.21': 'soljson-v0.8.21+commit.d9974bed.js'
}

@Component({
  selector: 'app-web3-sandbox',
  templateUrl: './web3-sandbox.component.html',
  styleUrls: ['./web3-sandbox.component.scss'],
  imports: [
    CodemirrorModule,
    FormsModule,
    MatButtonModule,
    MatIconModule,
    TranslateModule,
    MatFormFieldModule,
    MatLabel,
    MatInputModule
  ]
})
export class Web3SandboxComponent implements OnInit {
  private readonly keysService = inject(KeysService)
  private readonly snackBarHelperService = inject(SnackBarHelperService)
  private readonly changeDetectorRef = inject(ChangeDetectorRef)

  private readonly chainChangedHandler = this.handleChainChanged.bind(this)

  ngOnInit (): void {
    this.handleAuth().catch(() => {
      this.snackBarHelperService.open('WALLET_AUTH_FAILED', 'errorBar')
    })
    if (window.ethereum?.on) {
      window.ethereum.on('chainChanged', this.chainChangedHandler)
    }
  }

  ngOnDestroy (): void {
    if (window.ethereum?.removeListener) {
      window.ethereum.removeListener('chainChanged', this.chainChangedHandler)
    }
  }

  userData: Record<string, unknown> = {}
  session = false
  metamaskAddress = ''
  selectedContractName = ''
  compiledContracts: Record<string, any> | null = null
  deployedContractAddress = ''
  contractNames: string[] = []
  commonGweiValue = 0
  contractFunctions: Array<{
    name: string
    inputs: Array<{ name: string; type: string }>
    stateMutability: string
    type: string
    inputValues: string
    outputValue: string
    inputHints: string
    outputs: Array<{ type: string }>
  }> = []
  invokeOutput = ''
  selectedCompilerVersion = '0.8.21'
  compilerVersions: string[] = Object.keys(compilerReleases)
  compilerErrors: any[] = []
  code = `// SPDX-License-Identifier: MIT
pragma solidity ^0.8.14;
contract HelloWorld {
    function get() public pure returns (string memory) {
        return 'Hello Contracts';
    }
}`
  editorOptions = {
    mode: 'text/x-solidity',
    theme: 'dracula',
    lineNumbers: true,
    lineWrapping: true
  }

  /**
   * Compile solidity code using a whitelisted version; capture errors safely.
   */
  async compileAndFetchContracts (code: string): Promise<void> {
    this.deployedContractAddress = ''
    this.compilerErrors = []
    const selectedVersion = compilerReleases[this.selectedCompilerVersion]
    if (!selectedVersion) {
      this.snackBarHelperService.open('COMPILER_VERSION_NOT_FOUND', 'errorBar')
      return
    }

    try {
      const compilerInput = {
        version: `https://binaries.soliditylang.org/bin/${selectedVersion}`,
        contractBody: code
      }
      const output = await solidityCompiler(compilerInput)

      if (Array.isArray(output.errors) && output.errors.length > 0 && !output.contracts) {
        this.compiledContracts = null
        this.compilerErrors.push(...output.errors)
        return
      }

      const compiled = output?.contracts?.Compiled_Contracts
      if (!compiled || typeof compiled !== 'object') {
        this.snackBarHelperService.open('COMPILER_OUTPUT_INVALID', 'errorBar')
        return
      }

      this.compiledContracts = compiled
      this.contractNames = Object.keys(compiled)
      this.selectedContractName = this.contractNames[0] ?? ''
      this.snackBarHelperService.open('COMPILE_SUCCESS', 'infoBar')
    } catch (error: any) {
      this.compilerErrors.push(error?.message ?? 'Unknown compile error')
      this.snackBarHelperService.open('COMPILE_FAILED', 'errorBar')
    }
  }

  /**
   * Deploy the selected contract with minimal payable options.
   */
  async deploySelectedContract (): Promise<void> {
    if (!this.ensureSession()) return
    if (!this.compiledContracts || !this.selectedContractName) {
      this.snackBarHelperService.open('NO_COMPILED_CONTRACT', 'errorBar')
      return
    }

    try {
      const selectedContract = this.compiledContracts[this.selectedContractName]
      if (!selectedContract) {
        this.snackBarHelperService.open('SELECTED_CONTRACT_NOT_FOUND', 'errorBar')
        return
      }
      const provider = new ethers.BrowserProvider(window.ethereum!)
      const signer = await provider.getSigner()

      const contractBytecode: string = selectedContract?.evm?.bytecode?.object
      const contractAbi: any[] = selectedContract?.abi
      if (!contractBytecode || !Array.isArray(contractAbi)) {
        this.snackBarHelperService.open('INVALID_CONTRACT_ARTIFACTS', 'errorBar')
        return
      }

      const factory = new ethers.ContractFactory(contractAbi, contractBytecode, signer)
      const transactionOptions: ethers.TransactionRequest = {}

      if (this.commonGweiValue > 0) {
        // Value must be in wei for payable functions. Treat commonGweiValue defensively.
        transactionOptions.value = ethers.parseUnits(String(this.commonGweiValue), 'gwei')
      }

      const contract = await factory.deploy(transactionOptions)
      await contract.waitForDeployment()
      this.deployedContractAddress = await contract.getAddress()

      this.contractFunctions = (contractAbi as any[])
        .filter((item) => item?.type === 'function')
        .map((func) => ({
          ...func,
          inputValues: '',
          outputValue: '',
          inputHints: this.getInputHints(func.inputs ?? [])
        }))

      this.snackBarHelperService.open('DEPLOY_SUCCESS', 'infoBar')
    } catch (error: any) {
      this.snackBarHelperService.open('DEPLOY_FAILED', 'errorBar')
    }
  }

  getInputHints (inputs: { name: string, type: string }[]): string {
    return inputs.map((input) => `${input.name}: ${input.type}`).join(', ')
  }

  parseInputValue (value: string, type: string): unknown {
    switch (type) {
      case 'bool':
        return value.trim().toLowerCase() === 'true'
      case 'uint256':
      case 'int256':
        return BigInt(value.trim())
      default:
        return value.trim()
    }
  }

  /**
   * Refactored to reduce cognitive complexity:
   * - Early returns for session and prerequisites
   * - Extracted helpers for inputs, transaction options, and result handling
   */
  async invokeFunction (func: {
    name: string
    inputs: Array<{ name: string; type: string }>
    outputs: Array<{ type: string }>
    stateMutability: string
    inputValues: string
    outputValue: string
  }): Promise<void> {
    if (!this.ensureSession()) return
    if (!this.deployedContractAddress || !ethers.isAddress(this.deployedContractAddress)) {
      this.snackBarHelperService.open('INVALID_DEPLOYED_ADDRESS', 'errorBar')
      return
    }
    if (!this.compiledContracts || !this.selectedContractName) {
      this.snackBarHelperService.open('NO_COMPILED_CONTRACT', 'errorBar')
      return
    }

    try {
      const selectedContract = this.compiledContracts[this.selectedContractName]
      const abi: any[] = selectedContract?.abi
      if (!Array.isArray(abi)) {
        this.snackBarHelperService.open('INVALID_CONTRACT_ABI', 'errorBar')
        return
      }

      const provider = new ethers.BrowserProvider(window.ethereum!)
      const signer = await provider.getSigner()
      const contract = new ethers.Contract(this.deployedContractAddress, abi, signer)

      const inputs = this.buildInputs(func)
      const txOptions = this.buildTxOptions()

      const result = await (contract as any)[func.name](...inputs, txOptions)
      this.handleFunctionResult(func, result)
    } catch (error: any) {
      this.setFunctionOutput(func.name, error?.message ?? 'Unknown error')
      this.snackBarHelperService.open('FUNCTION_INVOKE_FAILED', 'errorBar')
    }
  }

  private buildInputs (func: { inputs: Array<{ type: string }>; inputValues: string }): unknown[] {
    if (!func.inputValues || func.inputValues.trim() === '') return []
    const rawValues = func.inputValues.split(',').map(v => v.trim())
    return rawValues.map((value, index) => {
      const inputType = func.inputs[index]?.type ?? 'string'
      return this.parseInputValue(value, inputType)
    })
  }

  private buildTxOptions (): ethers.TransactionRequest {
    const opts: ethers.TransactionRequest = {}
    if (this.commonGweiValue > 0) {
      opts.value = ethers.parseUnits(String(this.commonGweiValue), 'gwei')
    }
    return opts
  }

  private handleFunctionResult (func: { name: string; outputs: Array<{ type: string }>; stateMutability: string }, result: any): void {
    const isReadOnly = func.stateMutability === 'view' || func.stateMutability === 'pure'
    if (isReadOnly && Array.isArray(func.outputs) && func.outputs.length > 0) {
      const outputValue = Array.isArray(result) ? String(result[0]) : String(result)
      this.setFunctionOutput(func.name, outputValue)
      return
    }
    // For non-view functions, show a generic success message; avoid leaking raw transactions.
    this.setFunctionOutput(func.name, 'Transaction submitted')
  }

  private setFunctionOutput (funcName: string, value: string): void {
    const target = this.contractFunctions.find(f => f.name === funcName)
    if (!target) return
    target.outputValue = value
    // Trigger change detection after mutation
    this.changeDetectorRef.detectChanges()
  }

  async handleChainChanged (): Promise<void> {
    await this.handleAuth()
  }

  /**
   * Authenticate and ensure Sepolia network; avoid leaking errors to UI.
   */
  async handleAuth (): Promise<void> {
    try {
      const { isConnected } = getAccount()
      if (isConnected) await disconnect()

      if (!window.ethereum) {
        this.session = false
        this.snackBarHelperService.open('PLEASE_INSTALL_WEB3_WALLET', 'errorBar')
        return
      }

      const provider = await connect({ connector: new InjectedConnector() })
      const account = provider?.account
      const chainId = String(provider?.chain?.id ?? '')

      this.metamaskAddress = account ?? ''
      this.userData = {
        address: account,
        chain: provider?.chain?.id,
        network: 'evm'
      }

      // Request Sepolia chain registration (non-blocking)
      try {
        await window.ethereum.request({
          method: 'wallet_addEthereumChain',
          params: [{
            chainId: '0xaa36a7',
            chainName: 'Sepolia Test Network',
            nativeCurrency: { name: 'SepoliaETH', symbol: 'ETH', decimals: 18 },
            rpcUrls: ['https://ethereum-sepolia.blockpi.network/v1/rpc/public'],
            blockExplorerUrls: ['https://sepolia.etherscan.io/']
          }]
        })
      } catch {
        // Ignore addChain failure; user may already have it.
      }

      const targetChainId = '11155111' // Sepolia decimal
      if (!account || chainId !== targetChainId) {
        this.session = false
        this.snackBarHelperService.open('PLEASE_CONNECT_TO_SEPOLIA_NETWORK', 'errorBar')
      } else {
        this.session = true
      }

      this.changeDetectorRef.detectChanges()
    } catch {
      this.session = false
      this.snackBarHelperService.open('WALLET_AUTH_FAILED', 'errorBar')
    }
  }

  /**
   * Guard helper to ensure session is active.
   */
  private ensureSession (): boolean {
    if (!this.session) {
      this.snackBarHelperService.open('PLEASE_CONNECT_WEB3_WALLET', 'errorBar')
      return false
    }
    return true
  }
}
