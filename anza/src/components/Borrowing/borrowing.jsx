import '../../static/css/BorrowingPage.css';
import '../../static/css/NftTable.css';
import React, { useEffect, useState } from 'react';
import { ethers } from 'ethers';
import config from '../../config.json';

import { setPageTitle } from '../../utils/titleUtils';
import { getSubAddress } from '../../utils/addressUtils';
import { getNetworkName } from '../../utils/networkUtils';
import { checkIfWalletIsConnected as checkConnection, connectWallet } from '../../utils/window/ethereumConnect';

import { listenerLoanContractCreated } from '../../utils/events/listenersLoanContractFactory';
import { setAnzaDebtTokenMetadata, postAnzaDebtTokenIPFS } from '../../utils/adt/adtIPFS';
import { mintAnzaDebtToken } from '../../utils/adt/adtContract';

import { clientCreateTokensPortfolio as createTokensPortfolio } from '../../db/clientCreateTokensPortfolio';
import { clientUpdatePortfolioLeveragedStatus as updatePortfolioLeveragedStatus } from '../../db/clientUpdateTokensPortfolio';
import { clientReadBorrowerNotSignedJoin as readBorrowerNotSignedJoin } from '../../db/clientReadJoin';

import { createTokensLeveraged } from '../../db/clientCreateTokensLeveraged';
import { createTokensDebt } from '../../db/clientCreateTokensDebt';

import abi_ERC721 from '../../artifacts/@openzeppelin/contracts/token/ERC721/IERC721.sol/IERC721.json'
import abi_LoanContractFactory from '../../artifacts/contracts/social/LoanContractFactory.sol/LoanContractFactory.json';

export default function BorrowingPage() {
    const [isPageLoad, setIsPageLoad] = useState(true);
    const [newContract, setNewContract] = useState('');
    const [currentAccount, setCurrentAccount] = useState(null);
    const [currentChainId, setCurrentChainId] = useState(null);
    const [currentAvailableNftsTable, setCurrentAvailableNftsTable] = useState(null);
    const [currentToken, setCurrentToken] = useState({ address: null, id: null });

    useEffect(() => {
        console.log('Page loading...');
        if (!!isPageLoad) pageLoadSequence();
    }, []);

    useEffect(() => {
        if (!!currentToken.address) tokenSelectionChangeSequence();
    }, [currentToken]);

    useEffect(() => {
        if (!!newContract) newContractCreatedSequence();
    }, [newContract])
    
    /* ---------------------------------------  *
     *       EVENT SEQUENCE FUNCTIONS           *
     * ---------------------------------------  */
    const pageLoadSequence = async () => {
        /**
         * Sequence when page is loaded.
         */

        // Set page title
        setPageTitle('Borrowing');

        // Set account and network
        const { account, chainId } = await checkIfWalletIsConnected();
        console.log(`Account: ${account}`);
        console.log(`Network: ${chainId}`);

        // Update nft.available table
        updateNftPortfolio(account);

        // Render table of potential NFTs
        const [availableNftsTable, token] = await renderNftTable(account);
        setCurrentToken({ address: token.address, id: token.id });
        setCurrentAvailableNftsTable(availableNftsTable);

        setIsPageLoad(false);
    }

    const tokenSelectionChangeSequence = async () => {
        // Update terms enable/disable
        const terms = document.getElementsByName(`terms-${currentAccount}`);
        [...terms].forEach((term) => { 
            term.disabled = `terms-${currentToken.address}-${currentToken.id}` != term.id;
        });
    }

    const newContractCreatedSequence = async () => {
        console.log('new contract created!');

        await updatePortfolioLeveragedStatus(newContract, 'Y');

        // Render table of potential NFTs
        const [availableNftsTable, _] = await renderNftTable(currentAccount);
        setCurrentAvailableNftsTable(availableNftsTable);

        window.location.reload();

        setNewContract('');
    }

    /* ---------------------------------------  *
     *           FRONTEND CALLBACKS             *
     * ---------------------------------------  */
    const callback__ConnectWallet = async () => {
        /**
         * Connect ethereum wallet callback
         */
        const account = await connectWallet();
        setCurrentAccount(account);
    }

    const callback__CreateLoanContract = async () => {
        const { ethereum } = window;
        const provider = new ethers.providers.Web3Provider(ethereum);
        const signer = provider.getSigner(currentAccount);

        // Set LoanContractFactory to operator
        let LoanContractFactory = new ethers.Contract(
            config.LoanContractFactory,
            abi_LoanContractFactory.abi,
            signer
        );

        const tokenContract = new ethers.Contract(
            currentToken.address,
            abi_ERC721.abi,
            signer
        );
        let tx = await tokenContract.setApprovalForAll(LoanContractFactory.address, true);
        await tx.wait();

        // Get selected token terms
        const principal = document.getElementsByClassName(`principal-${currentToken.address}-${currentToken.id}`)[0].value;
        const fixedInterestRate = document.getElementsByClassName(`fixedInterestRate-${currentToken.address}-${currentToken.id}`)[0].value;
        const duration = document.getElementsByClassName(`duration-${currentToken.address}-${currentToken.id}`)[0].value;
        const adtSelectElement = document.getElementsByClassName(`adt-${currentToken.address}-${currentToken.id}`)[0];
        const adtSelect = adtSelectElement.options[adtSelectElement.options.selectedIndex].text === 'Y';
        
        // Set IPFS debt metadata object for AnzaDebtToken
        const debtObj = await setAnzaDebtTokenMetadata(currentAccount);

        // Create new LoanContract
        tx = await LoanContractFactory.createLoanContract(
            config.LoanContract,
            currentToken.address,
            ethers.BigNumber.from(currentToken.id),
            ethers.utils.parseEther(principal),
            fixedInterestRate,
            duration
        );
        await tx.wait();

        const [cloneAddress, tokenContractAddress, tokenId] = await listenerLoanContractCreated(tx, LoanContractFactory);

        // Update databases
        const primaryKey = `${tokenContractAddress}_${tokenId.toString()}`;

        createTokensLeveraged(
            primaryKey,
            cloneAddress, 
            currentAccount, 
            tokenContractAddress, 
            tokenId.toString(), 
            ethers.constants.AddressZero,
            ethers.utils.parseEther(principal).toString(),
            fixedInterestRate,
            duration,
            'Y', 
            'N'
        );

        if (adtSelect) {
            // Set IPFS LoanContract metadata object for AnzaDebtToken
            const loanContractObj = {
                loanContractAddress: cloneAddress,
                borrowerAddress: currentAccount,
                collateralTokenAddress: currentToken.address,
                collateralTokenId: currentToken.id,
                lenderAddress: ethers.constants.AddressZero,
                principal: principal,
                fixedInterestRate: fixedInterestRate,
                duration: duration
            }

            // Post AnzaDebtToken to IPFS
            let debtTokenAddress, debtTokenId, debtTokenURI;
            debtTokenURI = await postAnzaDebtTokenIPFS(debtObj, loanContractObj);

            // Mint AnzaDebtToken with IPFS URI
            [debtTokenAddress, debtTokenId, debtTokenURI] = await mintAnzaDebtToken(currentAccount, cloneAddress, debtTokenURI);
            console.log(debtTokenURI);

            createTokensDebt(
                primaryKey,
                debtTokenURI,
                debtTokenAddress,
                debtTokenId,
                principal
            );
        }

        setNewContract(primaryKey);
    }

    const callback__SetContractParams = async ({ target }) => {
        const [tokenAddress, tokenId] = target.value.split('-');
        if (currentToken.address === tokenAddress && currentToken.id === tokenId) {
            // Do nothing
            return;
        }

        setCurrentToken({ address: tokenAddress, id: tokenId });
    }
    
    /* ---------------------------------------  *
     *        PAGE MODIFIED FUNCTIONS           *
     * ---------------------------------------  */
    const checkIfWalletIsConnected = async () => {
        /**
         * Connect wallet state change function.
         */
        const { account, chainId } = await checkConnection();
        setCurrentChainId (chainId);
        setCurrentAccount(account);

        // set wallet event listeners
        const { ethereum } = window;
        ethereum.on('accountsChanged', () => window.location.reload());
        ethereum.on('chainChanged', () => window.location.reload());

        return { account, chainId };
    }

    /* ---------------------------------------  *
     *       DATABASE MODIFIER FUNCTIONS        *
     * ---------------------------------------  */
    const updateNftPortfolio = async (account=currentAccount) => {
        if (!account) { return; }

        // Get tokens owned
        const tokensOwned = config.DEMO_TOKENS[account];
        if (!tokensOwned) {
            console.log("No tokens owned.");
            return;
        }

        // Format tokens owned for database update
        const portfolioVals = [];
        Object.keys(tokensOwned).map((i) => {
            let primaryKey = `${tokensOwned[i].tokenContractAddress}_${tokensOwned[i].tokenId.toString()}`;

            portfolioVals.push([
                primaryKey,
                account,
                tokensOwned[i].tokenContractAddress,
                tokensOwned[i].tokenId.toString(),
            ]);
        });

        // Update portfolio database
        await createTokensPortfolio(portfolioVals);
    }

    /* ---------------------------------------  *
     *           FRONTEND RENDERING             *
     * ---------------------------------------  */
    const renderNftTable = async (account) => {
        if (!account) { return [null, { address: null, id: null}]; }

        // Get non leveraged tokens
        const tokens = await readBorrowerNotSignedJoin(account);
        if (!tokens.length) { return [null, { address: null, id: null}]; }

        // Create token elements
        const tokenElements = [];
        tokenElements.push(
            Object.keys(tokens).map((i) => {
                return (
                    <tr key={`tr-${tokens[i].tokenContractAddress}-${tokens[i].tokenId}`}>
                        <td key={`td-radio-${tokens[i].tokenContractAddress}-${tokens[i].tokenId}`} id={`id-radio-${tokens[i].tokenContractAddress}-${tokens[i].tokenId}`}><input
                            type='radio'
                            key={`radio-${tokens[i].tokenContractAddress}-${tokens[i].tokenId}`}
                            name={`radio-${tokens[i].ownerAddress}`}
                            value={`${tokens[i].tokenContractAddress}-${tokens[i].tokenId}`}
                            defaultChecked={i==='0'}
                            onClick={callback__SetContractParams}
                        /></td>
                        <td key={`address-${tokens[i].tokenContractAddress}-${tokens[i].tokenId}`} id={`id-address-${i}`}>{getSubAddress(tokens[i].tokenContractAddress)}</td>
                        <td key={`tokenId-${tokens[i].tokenContractAddress}-${tokens[i].tokenId}`}  id={`id-tokenId-${i}`}>{tokens[i].tokenId}</td>
                        <td key={`td-principal-${tokens[i].tokenContractAddress}-${tokens[i].tokenId}`} id={`id-text-${tokens[i].tokenContractAddress}-${tokens[i].tokenId}`}><input
                            type='text'
                            key={`text-principal-${tokens[i].tokenContractAddress}-${tokens[i].tokenId}`}
                            id={`terms-${tokens[i].tokenContractAddress}-${tokens[i].tokenId}`}
                            name={`terms-${tokens[i].ownerAddress}`}
                            className={`principal-${tokens[i].tokenContractAddress}-${tokens[i].tokenId}`}
                            defaultValue={ethers.utils.formatEther(config.DEFAULT_TEST_VALUES.PRINCIPAL)}
                            disabled={i!=='0'}
                        /></td>
                        <td key={`td-fixedInterestRate-${tokens[i].tokenContractAddress}-${tokens[i].tokenId}`} id={`id-text-${tokens[i].tokenContractAddress}-${tokens[i].tokenId}`}><input
                            type='text'
                            key={`text-fixedInterestRate-${tokens[i].tokenContractAddress}-${tokens[i].tokenId}`}
                            id={`terms-${tokens[i].tokenContractAddress}-${tokens[i].tokenId}`}
                            name={`terms-${tokens[i].ownerAddress}`}
                            className={`fixedInterestRate-${tokens[i].tokenContractAddress}-${tokens[i].tokenId}`}
                            defaultValue={config.DEFAULT_TEST_VALUES.FIXED_INTEREST_RATE}
                            disabled={i!=='0'}
                        /></td>
                        <td key={`td-duration-${tokens[i].tokenContractAddress}-${tokens[i].tokenId}`} id={`id-text-${tokens[i].tokenContractAddress}-${tokens[i].tokenId}`}><input
                            type='text'
                            key={`text-duration-${tokens[i].tokenContractAddress}-${tokens[i].tokenId}`}
                            id={`terms-${tokens[i].tokenContractAddress}-${tokens[i].tokenId}`}
                            name={`terms-${tokens[i].ownerAddress}`}
                            className={`duration-${tokens[i].tokenContractAddress}-${tokens[i].tokenId}`}
                            defaultValue={config.DEFAULT_TEST_VALUES.DURATION}
                            disabled={i!=='0'}
                        /></td>
                        <td key={`td-adt-${tokens[i].tokenContractAddress}-${tokens[i].tokenId}`} id={`id-text-${tokens[i].tokenContractAddress}-${tokens[i].tokenId}`}>
                            <select
                                key={`text-adt-${tokens[i].tokenContractAddress}-${tokens[i].tokenId}`}
                                id={`terms-${tokens[i].tokenContractAddress}-${tokens[i].tokenId}`}
                                name={`terms-${tokens[i].ownerAddress}`}
                                className={`adt-${tokens[i].tokenContractAddress}-${tokens[i].tokenId}`}
                                disabled={i!=='0'}
                            >
                                <option>Y</option><option>N</option>
                            </select>
                        </td>
                    </tr>
                )
            })
        );
        
        const availableNftsTable = (    
            <form className='form-table form-table-available-nfts'>
                <table className='table-available-nfts'>
                    <thead><tr>
                        <th></th>
                        <th><label>Contract</label></th>
                        <th><label>Token ID</label></th>
                        <th><label>Principal (ETH)</label></th>
                        <th><label>APR</label></th>
                        <th><label>Duration (days)</label></th>
                    </tr></thead>
                    <tbody>
                        {tokenElements}
                    </tbody>
                </table>
            </form>
        );

        return [availableNftsTable, { address: tokens[0].tokenContractAddress, id: tokens[0].tokenId }];
    }

    /* ---------------------------------------  *
     *         BORROWERPAGE.JSX RETURN           *
     * ---------------------------------------  */
    return (
        <main style={{ padding: '1rem 0' }}>
            <div className='buttongroup buttongroup-header'>
                <div className='button button-network'>{getNetworkName(currentChainId)}</div>
            {!!currentAccount
                ? (<div className='button button-ethereum button-connected'>{getSubAddress(currentAccount)}</div>)
                : (<div className='button button-ethereum button-connect-wallet' onClick={callback__ConnectWallet}>Connect Wallet</div>)
            }
            </div>
            <div className='container container-table container-table-available-nfts'>
                <h2>Available Collateral</h2>
                <div className='buttongroup buttongroup-body'>
                    <div className='button button-body' onClick={callback__CreateLoanContract}>Request Loan</div>
                </div>
                {currentAvailableNftsTable}
            </div>
        </main>
    );
}
