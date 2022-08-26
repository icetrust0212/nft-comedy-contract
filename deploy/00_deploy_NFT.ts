import { DeployFunction } from 'hardhat-deploy/types';
import { calculate_whitelist_root } from '../whitelist/utils';

const fn: DeployFunction = async function ({ deployments: { deploy }, ethers: { getSigners }, network }) {
  const deployer = (await getSigners())[0];
 
  const contractDeployed = await deploy('ComedyNFT', {
    from: deployer.address,
    log: true,
    skipIfAlreadyDeployed: false,
    args: [],
    proxy: {
      proxyContract: 'OpenZeppelinTransparentProxy',
    },
  });

  console.log('npx hardhat verify --network '+ network.name +  ' ' + contractDeployed.address);

};
fn.skip = async (hre) => {
  return false;
  // Skip this on kovan.
  const chain = parseInt(await hre.getChainId());
  return chain != 1;
};
fn.tags = ['Anero'];

export default fn;
